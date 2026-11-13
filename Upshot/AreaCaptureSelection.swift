import AppKit
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
    let snapshots: [AreaCaptureSnapshot]
    let frozen: Bool
    let source: CaptureSource?
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
    private let liveMagnifier = AreaSelectionLiveMagnifier()
    private var active = false
    private var frozen = true
    private(set) var isAllInOne = false
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

    func select(smartElement: Bool = false, allInOne: Bool = false) async throws -> AreaCaptureSelectionResult? {
        guard !active, !CaptureCountdownPresenter.shared.isRunning, !Task.isCancelled else { return nil }
        active = true
        defer { active = false; snapshots.removeAll(); windows.removeAll() }
        frozen = UpshotPreferences.areaSelectionFreezeScreen
        isAllInOne = allInOne
        mode = smartElement ? .element : allInOne ? UpshotPreferences.allInOneLastMode : .area
        status = nil
        start = nil
        highlightedRect = allInOne ? AreaSelectionMemory.lastSelectionRect : nil
        pointer = NSEvent.mouseLocation
        windows = Self.windowTargets()
        if smartElement && !AreaSelectionAccessibility.hasPermission {
            requestAccessibilityPermission()
            return nil
        }
        if mode == .element && !AreaSelectionAccessibility.hasPermission { mode = .area }
        if mode == .previousArea { highlightedRect = AreaSelectionMemory.previousScreenshotRect }
        snapshots = try await AreaCaptureSnapshot.captureAll()
        try Task.checkCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { finish(nil); return }
                showPanels()
            }
        } onCancel: {
            Task { @MainActor in self.finish(nil) }
        }
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
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish(nil) }
        }
        move(to: pointer)
        if !frozen && UpshotPreferences.areaSelectionMagnifier { startLiveMagnifier() }
        NSLog("Area selector opened: frozen=%d displays=%ld crosshair=%d magnifier=%d", frozen, snapshots.count, UpshotPreferences.areaSelectionCrosshair, UpshotPreferences.areaSelectionMagnifier)
        if isAllInOne { NSLog("All-In-One opened: mode=%@ restoredSelection=%d", mode.rawValue, highlightedRect != nil) }
    }

    private func startLiveMagnifier() {
        liveMagnifier.start(panelIDs: Set(panels.map { CGWindowID($0.windowNumber) }), snapshots: snapshots) { [weak self] in self?.redraw() }
    }

    func magnifierImage(for snapshot: AreaCaptureSnapshot) -> CGImage? {
        if !frozen { return liveMagnifier.displayID == snapshot.displayID ? liveMagnifier.image : nil }
        return snapshot.image.cropping(to: snapshot.magnifierPixelRect(at: pointer))
    }

    func magnifierSamplePosition(for snapshot: AreaCaptureSnapshot) -> CGPoint {
        frozen ? snapshot.magnifierSamplePosition(at: pointer) : liveMagnifier.samplePosition
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
        if !frozen && UpshotPreferences.areaSelectionMagnifier && liveMagnifier.image == nil { text += " · Live preview unavailable" }
        return text
    }

    func chooseMode(_ selected: AllInOneCaptureMode) {
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

    func mouseUp(at point: CGPoint) {
        move(to: point)
        commitSelection()
    }

    private func commitSelection() {
        if mode == .recording {
            complete(kind: .recording, rect: AreaSelectionMemory.lastSelectionRect ?? .zero)
            return
        }
        guard let rect = highlightedRect, rect.width >= 1, rect.height >= 1 else {
            start = nil
            if mode == .previousArea { status = "No previous screenshot area · A: area · Esc: cancel" }
            redraw()
            return
        }
        switch mode {
        case .area, .previousArea: complete(kind: .area, rect: rect)
        case .element:
            NSLog("Smart element selected: x=%.1f y=%.1f width=%.1f height=%.1f", rect.minX, rect.minY, rect.width, rect.height)
            complete(kind: .element, rect: rect)
        case .window:
            if let hoveredWindow { complete(kind: .window(hoveredWindow.id), rect: rect) }
        case .fullscreen:
            if let displayID = snapshots.first(where: { $0.frame == rect })?.displayID { complete(kind: .fullscreen(displayID), rect: rect) }
        case .scrolling: complete(kind: .scrolling, rect: rect)
        case .recording: break
        }
    }

    func cancel() { finish(nil) }

    func toggleCrosshair() {
        UpshotPreferences.areaSelectionCrosshair.toggle()
        NSLog("Area crosshair changed: enabled=%d", UpshotPreferences.areaSelectionCrosshair)
        redraw()
    }

    func toggleMagnifier() {
        UpshotPreferences.areaSelectionMagnifier.toggle()
        NSLog("Area magnifier changed: enabled=%d", UpshotPreferences.areaSelectionMagnifier)
        if active && !frozen {
            if UpshotPreferences.areaSelectionMagnifier { startLiveMagnifier() } else { liveMagnifier.stop() }
        }
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
        case 53: finish(nil)
        case 49: chooseMode(mode == .window ? .area : .window)
        case 36, 76: commitSelection()
        default: break
        }
    }

    private func complete(kind: AreaCaptureSelectionResult.Kind, rect: CGRect) {
        NSLog("Area selector selected: mode=%@ x=%.1f y=%.1f width=%.1f height=%.1f", mode.rawValue, rect.minX, rect.minY, rect.width, rect.height)
        let target: WindowTarget?
        if case .window(let id) = kind {
            target = windows.first { $0.id == id }
        } else {
            target = Self.target(in: rect, windows: windows)
        }
        if isAllInOne { AreaSelectionMemory.rememberSelection(mode: mode, rect: rect) }
        finish(AreaCaptureSelectionResult(kind: kind, rect: rect, snapshots: snapshots, frozen: frozen, source: target?.source))
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
        liveMagnifier.stop()
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

private final class AreaCaptureSelectionView: NSView {
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
    override func mouseUp(with event: NSEvent) { selector.mouseUp(at: globalPoint(event)) }
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
