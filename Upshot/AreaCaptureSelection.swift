import AppKit
import ScreenCaptureKit
import SwiftUI

struct AreaCaptureSelectionResult {
    enum Kind {
        case area
        case element
        case window(CGWindowID)
        case fullscreen(CGDirectDisplayID)
        case scrolling
        case recording
    }

    let kind: Kind
    let rect: CGRect
    var snapshots: [AreaCaptureSnapshot]
    let frozen: Bool
    let source: CaptureSource?
    var cursor: ScreenshotCursorSnapshot?
    var skipBackgroundPreset = false
    var capturedAt = Date()
    var composedImage: CGImage?
    var selectionTime: TimeInterval?
    var desktopIconLease: UUID?

    func logTiming(composedAt time: TimeInterval, acquisition: String, frames: [AreaCaptureSnapshot]? = nil) {
        guard let selectionTime else { return }
        for snapshot in frames ?? snapshots where snapshot.frame.intersects(rect) {
            if let presentationTime = snapshot.presentationTime {
                NSLog("Area capture timing: acquisition=%@ display=%u selectionToFrameMs=%.3f selectionToComposedMs=%.3f",
                      acquisition, snapshot.displayID, (presentationTime - selectionTime) * 1000, (time - selectionTime) * 1000)
            } else {
                NSLog("Area capture timing: acquisition=%@ display=%u selectionToFrameMs=unavailable selectionToComposedMs=%.3f",
                      acquisition, snapshot.displayID, (time - selectionTime) * 1000)
            }
        }
    }
}

@MainActor
@Observable
final class AreaCaptureSelection {
    static let shared = AreaCaptureSelection()

    struct WindowTarget {
        let id: CGWindowID
        let processID: pid_t
        let frame: CGRect
        let source: CaptureSource
    }

    private var panels: [NSPanel] = []
    private var views: [AreaCaptureSelectionView] = []
    private var continuation: CheckedContinuation<AreaCaptureSelectionResult?, Never>?
    private var snapshots: [AreaCaptureSnapshot] = []
    private var windows: [WindowTarget] = []
    private var screenObserver: NSObjectProtocol?
    private var streams: [AreaCaptureFrameStream] = []
    private var desktopIconLease: UUID?
    private var selectionError: Error?
    private var cancelled = false
    private var delaySeconds = 0
    private var includeWindowShadow = false
    private var sessionID = UUID()
    private var active = false
    private var cursor: ScreenshotCursorSnapshot?
    private var frozen = true
    private(set) var isAllInOne = false
    private var isScrollingOnly = false
    private(set) var mode: AllInOneCaptureMode = .area
    private(set) var start: CGPoint?
    private(set) var pointer = CGPoint.zero
    private(set) var highlightedRect: CGRect?
    private var hoveredWindow: WindowTarget?
    private var status: String?

    var instruction: String {
        if let status { return status }
        switch mode {
        case .area: return highlightedRect == nil ? "Drag across displays · Space: window · E: element · Esc: cancel" : "Drag a new area or press Return · Esc: cancel"
        case .window: return "Click a window · Space: area · Esc: cancel"
        case .fullscreen: return "Click a display to capture · Esc: cancel"
        case .previousArea: return highlightedRect == nil ? "No previous screenshot area · A: area · Esc: cancel" : "Click or press Return to capture the previous area"
        case .element: return highlightedRect == nil ? "No accessible element here · E: area · Esc: cancel" : "Click an element · E: area · Esc: cancel"
        case .scrolling: return "Drag the scrolling capture area · Esc: cancel"
        case .recording: return "Click or press Return to open recording controls"
        }
    }

    func select(smartElement: Bool = false, allInOne: Bool = false, initialMode: AllInOneCaptureMode = .area, scrolling: Bool = false,
                delaySeconds: Int = 0, includeWindowShadow: Bool = false) async throws -> AreaCaptureSelectionResult? {
        guard !active, !CaptureCountdownPresenter.shared.isRunning, !Task.isCancelled else { return nil }
        cursor = ScreenshotCursorService.snapshot()
        active = true
        defer {
            active = false
            snapshots.removeAll()
            windows.removeAll()
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            DesktopIconVisibilityService.shared.endCapture(desktopIconLease)
            desktopIconLease = nil
        }
        cancelled = false
        let sessionID = UUID()
        self.sessionID = sessionID
        selectionError = nil
        self.delaySeconds = delaySeconds
        self.includeWindowShadow = includeWindowShadow
        frozen = UpshotPreferences.areaSelectionFreezeScreen
        isAllInOne = allInOne
        isScrollingOnly = scrolling
        mode = scrolling ? .scrolling : smartElement ? .element : allInOne ? UpshotPreferences.allInOneLastMode : initialMode
        status = nil
        start = nil
        highlightedRect = allInOne ? AreaSelectionMemory.lastSelectionRect : nil
        pointer = NSEvent.mouseLocation
        windows = Self.windowTargets()
        if smartElement && !AreaSelectionAccessibility.hasPermission {
            requestAccessibilityPermission()
            return nil
        }
        if mode == .element && !AreaSelectionAccessibility.hasPermission {
            mode = .area
            requestAccessibilityPermission()
            NSLog("All-In-One element mode unavailable without Accessibility permission; using area mode")
        }
        if mode == .previousArea { highlightedRect = AreaSelectionMemory.previousScreenshotRect }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                NSLog("Area selector display layout changed: cancelling capture")
                self?.cancel()
            }
        }
        do {
            let result = try await withTaskCancellationHandler {
                desktopIconLease = try await DesktopIconVisibilityService.shared.beginCapture()
                snapshots = try await AreaCaptureSnapshot.captureAll(desktopIconsPrepared: true)
                try Task.checkCancellation()
                if !frozen && !cancelled { try await startStreams() }
                try Task.checkCancellation()
                if let selectionError { throw selectionError }
                guard !cancelled else { return nil as AreaCaptureSelectionResult? }
                return await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    if Task.isCancelled || cancelled { finish(nil); return }
                    showPanels()
                }
            } onCancel: {
                Task { @MainActor in
                    if self.sessionID == sessionID { self.cancel() }
                }
            }
            try await stopStreams()
            if let selectionError { throw selectionError }
            guard !cancelled && !Task.isCancelled else { return nil }
            if result?.desktopIconLease != nil { desktopIconLease = nil }
            return result
        } catch {
            try? await stopStreams()
            throw error
        }
    }

    private func startStreams() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let application = content.applications.first(where: { $0.processID == getpid() }) else { throw CocoaError(.fileReadUnknown) }
        let coverIDs = DesktopIconVisibilityService.shared.coverWindowIDs
        let covers = content.windows.filter { coverIDs.contains($0.windowID) }
        guard covers.count == coverIDs.count else { throw CocoaError(.fileReadUnknown) }
        for snapshot in snapshots {
            try Task.checkCancellation()
            guard !cancelled else { return }
            guard let display = content.displays.first(where: { $0.displayID == snapshot.displayID }) else { throw CocoaError(.fileReadUnknown) }
            let stream = AreaCaptureFrameStream(displayID: snapshot.displayID, frame: snapshot.frame, didUpdate: { [weak self] in
                if UpshotPreferences.areaSelectionMagnifier { self?.redraw() }
            }, didFail: { [weak self] error in
                self?.selectionError = error
                self?.cancel()
            })
            streams.append(stream)
            try await stream.start(display: display, excluding: application, covers: covers)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !streams.allSatisfy(\.isReady) && !cancelled {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CocoaError(.fileReadUnknown) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func stopStreams() async throws {
        guard !streams.isEmpty else { return }
        var failure: Error?
        var stopped = 0
        var failed = 0
        for stream in streams {
            do { try await stream.stop(); stopped += 1 }
            catch { failure = failure ?? error; failed += 1 }
        }
        streams.removeAll()
        NSLog("Area capture streams released: retained=0 stopped=%ld failed=%ld", stopped, failed)
        if let failure { throw failure }
    }

    private func requestAccessibilityPermission() {
        AreaSelectionAccessibility.requestPermission()
        CaptureTextFeedbackPresenter.shared.showFailure(title: "Enable Accessibility for smart element capture", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
    }

    private func showPanels() {
        for snapshot in snapshots {
            let panel = AreaCaptureSelectionPanel(contentRect: snapshot.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = frozen
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let view = AreaCaptureSelectionView(snapshot: snapshot, frozen: frozen, selector: self)
            panel.contentView = view
            panels.append(panel)
            views.append(view)
            panel.orderFrontRegardless()
        }
        let panel = panels.first { $0.frame.contains(pointer) } ?? panels.first
        panel?.makeKey()
        panel?.makeFirstResponder(panel?.contentView)
        if highlightedRect == nil { move(to: pointer) } else { redraw() }
        NSLog("Area selector opened: frozen=%d displays=%ld crosshair=%d magnifier=%d", frozen, snapshots.count, UpshotPreferences.areaSelectionCrosshair, UpshotPreferences.areaSelectionMagnifier)
        if isAllInOne { NSLog("All-In-One opened: mode=%@ restoredSelection=%d", mode.rawValue, highlightedRect != nil) }
    }

    func magnifierImage(for snapshot: AreaCaptureSnapshot) -> CGImage? {
        if !frozen { return streams.first { $0.displayID == snapshot.displayID }?.magnifierImage(at: pointer, geometry: snapshot) }
        return snapshot.image.cropping(to: snapshot.magnifierPixelRect(at: pointer))
    }

    func magnifierSamplePosition(for snapshot: AreaCaptureSnapshot) -> CGPoint {
        snapshot.magnifierSamplePosition(at: pointer)
    }

    func readout(for snapshot: AreaCaptureSnapshot) -> String {
        let pixel = snapshot.pixelPoint(at: pointer)
        let x = Int(pixel.x)
        let y = Int(pixel.y)
        var text = "X \(x) Y \(y) px"
        if let highlightedRect {
            let scale = snapshots.filter { $0.frame.intersects(highlightedRect) }.map(\.scale).max() ?? snapshot.scale
            text += " · \(Int(ceil(highlightedRect.width * scale))) × \(Int(ceil(highlightedRect.height * scale))) px"
        }
        if !frozen && UpshotPreferences.areaSelectionMagnifier && !streams.contains(where: { $0.displayID == snapshot.displayID && $0.isReady }) { text += " · Live preview unavailable" }
        return text
    }

    func chooseMode(_ selected: AllInOneCaptureMode) {
        guard !isScrollingOnly else { return }
        guard isAllInOne || [.area, .window, .element].contains(selected) else { return }
        if selected == .element && !AreaSelectionAccessibility.hasPermission {
            finish(nil)
            requestAccessibilityPermission()
            return
        }
        mode = selected
        status = nil
        start = nil
        highlightedRect = selected == .previousArea ? AreaSelectionMemory.previousScreenshotRect : nil
        if selected == .area || selected == .scrolling { highlightedRect = AreaSelectionMemory.lastSelectionRect }
        move(to: NSEvent.mouseLocation)
        NSLog("Area selection mode changed: mode=%@", mode.rawValue)
        if selected == .recording || selected == .previousArea { commitSelection() }
    }

    func move(to point: CGPoint) {
        pointer = point
        if let start {
            let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
            highlightedRect = AreaCaptureSnapshot.pixelAlignedRect(rect, snapshots: snapshots)
        } else {
            switch mode {
            case .element:
                hoveredWindow = windows.first { $0.frame.contains(point) }
                highlightedRect = hoveredWindow.flatMap { AreaSelectionAccessibility.frame(at: point, processID: $0.processID) }.map { AreaCaptureSnapshot.pixelAlignedRect($0, snapshots: snapshots) }
            case .window:
                hoveredWindow = windows.first { $0.frame.contains(point) }
                highlightedRect = hoveredWindow?.frame
            case .fullscreen:
                highlightedRect = snapshots.first { $0.frame.contains(point) }?.frame
            case .area, .previousArea, .scrolling, .recording: break
            }
        }
        redraw()
    }

    func mouseDown(at point: CGPoint) {
        move(to: point)
        guard mode == .area || mode == .scrolling else { return }
        start = point
        highlightedRect = nil
        redraw()
    }

    func mouseUp(at point: CGPoint, eventTime: TimeInterval) {
        move(to: point)
        commitSelection(eventTime: eventTime)
    }

    private func commitSelection(eventTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if mode == .recording {
            complete(kind: .recording, rect: AreaSelectionMemory.lastSelectionRect ?? .zero, eventTime: eventTime)
            return
        }
        guard let rect = highlightedRect, rect.width >= 1, rect.height >= 1 else {
            start = nil
            if mode == .previousArea { status = "No previous screenshot area · A: area · Esc: cancel" }
            redraw()
            return
        }
        switch mode {
        case .area, .previousArea: complete(kind: .area, rect: rect, eventTime: eventTime)
        case .element:
            NSLog("Smart element selected: x=%.1f y=%.1f width=%.1f height=%.1f", rect.minX, rect.minY, rect.width, rect.height)
            complete(kind: .element, rect: rect, eventTime: eventTime)
        case .window:
            if let hoveredWindow { complete(kind: .window(hoveredWindow.id), rect: rect, eventTime: eventTime) }
        case .fullscreen:
            if let displayID = snapshots.first(where: { $0.frame == rect })?.displayID { complete(kind: .fullscreen(displayID), rect: rect, eventTime: eventTime) }
        case .scrolling: complete(kind: .scrolling, rect: rect, eventTime: eventTime)
        case .recording: break
        }
    }

    func cancel() { cancelled = true; finish(nil) }

    func toggleCrosshair() {
        UpshotPreferences.areaSelectionCrosshair.toggle()
        NSLog("Area crosshair changed: enabled=%d", UpshotPreferences.areaSelectionCrosshair)
        redraw()
    }

    func toggleMagnifier() {
        UpshotPreferences.areaSelectionMagnifier.toggle()
        NSLog("Area magnifier changed: enabled=%d", UpshotPreferences.areaSelectionMagnifier)
        redraw()
    }

    func keyDown(_ event: NSEvent) {
        if let character = event.charactersIgnoringModifiers?.lowercased() {
            if isAllInOne, let selected = AllInOneCaptureMode.allCases.first(where: { $0.shortcut == character }) {
                chooseMode(selected)
                return
            }
            switch character {
            case "a": chooseMode(.area); return
            case "e": chooseMode(mode == .element ? .area : .element); return
            case "x":
                toggleCrosshair()
                return
            case "m":
                toggleMagnifier()
                return
            default: break
            }
        }
        switch event.keyCode {
        case 53: cancel()
        case 49: chooseMode(mode == .window ? .area : .window)
        case 36, 76: commitSelection(eventTime: event.timestamp)
        default: break
        }
    }

    private func complete(kind: AreaCaptureSelectionResult.Kind, rect: CGRect, eventTime: TimeInterval) {
        NSLog("Area selector selected: mode=%@ x=%.1f y=%.1f width=%.1f height=%.1f", mode.rawValue, rect.minX, rect.minY, rect.width, rect.height)
        let target: WindowTarget?
        if case .window(let id) = kind {
            target = windows.first { $0.id == id }
        } else {
            target = Self.target(in: rect, windows: windows)
        }
        if isAllInOne { AreaSelectionMemory.rememberSelection(mode: mode, rect: rect) }
        let location = ActiveDisplayResolver.quartzPoint(fromAppKit: pointer)
        let captureCursor = cursor.map {
            ScreenshotCursorSnapshot(image: $0.image, pointSize: $0.pointSize, hotSpot: $0.hotSpot, location: location)
        }
        var result = AreaCaptureSelectionResult(kind: kind, rect: rect, snapshots: snapshots, frozen: frozen, source: target?.source, cursor: captureCursor)
        result.skipBackgroundPreset = NSEvent.modifierFlags.contains(.shift)
        result.selectionTime = eventTime
        result.capturedAt = Date(timeIntervalSinceNow: eventTime - ProcessInfo.processInfo.systemUptime)
        switch kind {
        case .scrolling, .recording: break
        default:
            let needsWindowShadow: Bool
            if case .window = kind { needsWindowShadow = includeWindowShadow } else { needsWindowShadow = false }
            if delaySeconds == 0 && !needsWindowShadow {
                do {
                    if !frozen {
                        result = try selectionUsingLiveFrames(result, eventTime: eventTime)
                    }
                    result.composedImage = try AreaCaptureSnapshot.composite(result.snapshots, in: rect)
                    result.logTiming(composedAt: ProcessInfo.processInfo.systemUptime, acquisition: frozen ? "frozen" : "stream")
                } catch {
                    selectionError = error
                    NSLog("Area capture selection failed: no usable frame at selection or composition failed error=%@", error.localizedDescription)
                    finish(nil)
                    return
                }
            } else {
                result.desktopIconLease = desktopIconLease
            }
        }
        finish(result)
    }

    private func selectionUsingLiveFrames(_ result: AreaCaptureSelectionResult, eventTime: TimeInterval) throws -> AreaCaptureSelectionResult {
        let selected = try streams.filter { $0.frame.intersects(result.rect) }.map { try $0.snapshot(for: eventTime) }
        guard !selected.isEmpty else { throw CocoaError(.fileReadUnknown) }
        var selection = result
        selection.snapshots = selected
        return selection
    }

    static func captureSource(in rect: CGRect) -> CaptureSource? {
        target(in: rect, windows: windowTargets())?.source
    }

    private static func target(in rect: CGRect, windows: [WindowTarget]) -> WindowTarget? {
        windows.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
            ?? windows.filter { $0.frame.intersects(rect) }.max {
                let left = $0.frame.intersection(rect)
                let right = $1.frame.intersection(rect)
                return left.width * left.height < right.width * right.height
            }
    }

    private func redraw() {
        for view in views { view.needsDisplay = true }
    }

    private func finish(_ result: AreaCaptureSelectionResult?) {
        guard let continuation else { return }
        self.continuation = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        snapshots.removeAll()
        windows.removeAll()
        NSLog("Area selector closed: cancelled=%d", result == nil)
        continuation.resume(returning: result)
    }

    private static func windowTargets() -> [WindowTarget] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let processID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 1, frame.height > 1 else { return nil }
            let application = NSRunningApplication(processIdentifier: processID)
            let source = CaptureSource(bundleIdentifier: application?.bundleIdentifier,
                                       appName: application?.localizedName ?? window[kCGWindowOwnerName as String] as? String ?? "Unknown",
                                       windowTitle: window[kCGWindowName as String] as? String)
            return WindowTarget(id: id, processID: processID, frame: ActiveDisplayResolver.appKitRect(fromQuartz: frame), source: source)
        }
    }
}

private final class AreaCaptureSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AreaCaptureSelectionView: NSView {
    let snapshot: AreaCaptureSnapshot
    let frozen: Bool
    unowned let selector: AreaCaptureSelection
    private var tracking: NSTrackingArea?

    init(snapshot: AreaCaptureSnapshot, frozen: Bool, selector: AreaCaptureSelection) {
        self.snapshot = snapshot
        self.frozen = frozen
        self.selector = selector
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        if selector.isAllInOne {
            let toolbar = NSHostingView(rootView: AllInOneCaptureToolbar(selector: selector))
            toolbar.sizingOptions = []
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(toolbar)
            NSLayoutConstraint.activate([
                toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
                toolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
                toolbar.widthAnchor.constraint(equalToConstant: min(snapshot.frame.width - 32, 820)),
                toolbar.heightAnchor.constraint(equalToConstant: snapshot.frame.width < 860 ? 128 : 90)
            ])
        }
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { frozen }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func keyDown(with event: NSEvent) { selector.keyDown(event) }
    override func mouseMoved(with event: NSEvent) { selector.move(to: globalPoint(event)) }
    override func mouseDragged(with event: NSEvent) { selector.move(to: globalPoint(event)) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        selector.mouseDown(at: globalPoint(event))
    }
    override func mouseUp(with event: NSEvent) { selector.mouseUp(at: globalPoint(event), eventTime: event.timestamp) }
    override func rightMouseDown(with event: NSEvent) { selector.cancel() }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        if frozen { context.draw(snapshot.image, in: bounds) }
        let selected = selector.highlightedRect?.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY)
        let dimming = NSBezierPath(rect: bounds)
        if let selected {
            let intersection = selected.intersection(bounds)
            if !intersection.isNull && !intersection.isEmpty { dimming.appendRect(intersection) }
        }
        dimming.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.25).setFill()
        dimming.fill()
        if let selected {
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: selected)
            path.lineWidth = 1
            path.stroke()
        }
        if snapshot.frame.contains(selector.pointer) {
            let point = CGPoint(x: selector.pointer.x - snapshot.frame.minX, y: selector.pointer.y - snapshot.frame.minY)
            AreaSelectionMagnifier.draw(in: context, bounds: bounds, point: point,
                                        image: selector.magnifierImage(for: snapshot), samplePosition: selector.magnifierSamplePosition(for: snapshot), readout: selector.readout(for: snapshot),
                                        showsCrosshair: UpshotPreferences.areaSelectionCrosshair,
                                        showsMagnifier: UpshotPreferences.areaSelectionMagnifier)
        }
        guard !selector.isAllInOne else { return }
        let text = selector.instruction
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: (bounds.width - size.width) / 2 - 16, y: 36, width: size.width + 32, height: 36)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 16, y: rect.minY + 10), withAttributes: attributes)
    }
}

extension AreaCaptureSelection {
    static func renderView(image: CGImage, mode: AllInOneCaptureMode, allInOne: Bool, crosshair: Bool) -> NSView {
        precondition(UpshotStorage.isRenderingStates)
        let selector = AreaCaptureSelection.shared
        let snapshot = AreaCaptureSnapshot(displayID: 0, frame: CGRect(x: 0, y: 0, width: 1000, height: 625), image: image)
        selector.snapshots = [snapshot]
        selector.frozen = true
        selector.mode = mode
        selector.isAllInOne = allInOne
        selector.pointer = CGPoint(x: 650, y: 370)
        selector.highlightedRect = crosshair ? nil : CGRect(x: 120, y: 175, width: 620, height: 330)
        return AreaCaptureSelectionView(snapshot: snapshot, frozen: true, selector: selector)
    }
}
