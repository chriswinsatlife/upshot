import AppKit

struct AreaCaptureSelectionResult {
    enum Kind {
        case area
        case element
        case window(CGWindowID)
    }

    let kind: Kind
    let rect: CGRect
    let snapshots: [AreaCaptureSnapshot]
    let frozen: Bool
    let source: CaptureSource?
}

@MainActor
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
    private(set) var elementSelection = false
    private(set) var windowSelection = false
    private(set) var start: CGPoint?
    private(set) var pointer = CGPoint.zero
    private(set) var highlightedRect: CGRect?
    private var hoveredWindow: WindowTarget?

    func select(smartElement: Bool = false) async throws -> AreaCaptureSelectionResult? {
        guard !active, !Task.isCancelled else { return nil }
        active = true
        defer { active = false; snapshots.removeAll(); windows.removeAll() }
        frozen = UpshotPreferences.areaSelectionFreezeScreen
        windowSelection = false
        elementSelection = smartElement
        start = nil
        highlightedRect = nil
        pointer = NSEvent.mouseLocation
        windows = Self.windowTargets()
        if smartElement && !AreaSelectionAccessibility.hasPermission {
            AreaSelectionAccessibility.requestPermission()
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Enable Accessibility for smart element capture", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
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
            Task { @MainActor in self?.finish(nil) }
        }
        move(to: pointer)
        if !frozen && UpshotPreferences.areaSelectionMagnifier {
            startLiveMagnifier()
        }
        NSLog("Area selector opened: frozen=%d displays=%ld crosshair=%d magnifier=%d", frozen, snapshots.count, UpshotPreferences.areaSelectionCrosshair, UpshotPreferences.areaSelectionMagnifier)
    }

    private func startLiveMagnifier() {
        liveMagnifier.start(panelIDs: Set(panels.map { CGWindowID($0.windowNumber) }), snapshots: snapshots) { [weak self] in self?.redraw() }
    }

    func magnifierImage(for snapshot: AreaCaptureSnapshot) -> CGImage? {
        if !frozen { return liveMagnifier.displayID == snapshot.displayID ? liveMagnifier.image : nil }
        let x = (pointer.x - snapshot.frame.minX) * snapshot.scale
        let y = (snapshot.frame.maxY - pointer.y) * snapshot.scale
        let rect = CGRect(x: min(max(0, floor(x) - 8), CGFloat(snapshot.image.width) - 17),
                          y: min(max(0, floor(y) - 8), CGFloat(snapshot.image.height) - 17), width: 17, height: 17)
        return snapshot.image.cropping(to: rect)
    }

    func magnifierSamplePosition(for snapshot: AreaCaptureSnapshot) -> CGPoint {
        if !frozen { return liveMagnifier.samplePosition }
        let x = (pointer.x - snapshot.frame.minX) * snapshot.scale
        let y = (snapshot.frame.maxY - pointer.y) * snapshot.scale
        let originX = min(max(0, floor(x) - 8), CGFloat(snapshot.image.width) - 17)
        let originY = min(max(0, floor(y) - 8), CGFloat(snapshot.image.height) - 17)
        return CGPoint(x: (floor(x) + 0.5 - originX) / 17, y: 1 - (floor(y) + 0.5 - originY) / 17)
    }

    func readout(for snapshot: AreaCaptureSnapshot) -> String {
        let x = Int(floor((pointer.x - snapshot.frame.minX) * snapshot.scale))
        let y = Int(floor((snapshot.frame.maxY - pointer.y) * snapshot.scale))
        var text = "X \(x) Y \(y) px"
        if let highlightedRect {
            let scale = snapshots.filter { $0.frame.intersects(highlightedRect) }.map(\.scale).max() ?? snapshot.scale
            text += " · \(Int(ceil(highlightedRect.width * scale))) × \(Int(ceil(highlightedRect.height * scale))) px"
        }
        if !frozen && UpshotPreferences.areaSelectionMagnifier && liveMagnifier.image == nil { text += " · Live preview unavailable" }
        return text
    }

    func move(to point: CGPoint) {
        pointer = point
        if let start {
            highlightedRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        } else if elementSelection {
            hoveredWindow = windows.first { $0.frame.contains(point) }
            highlightedRect = hoveredWindow.flatMap { AreaSelectionAccessibility.frame(at: point, processID: $0.processID) }
        } else if windowSelection {
            hoveredWindow = windows.first { $0.frame.contains(point) }
            highlightedRect = hoveredWindow?.frame
        }
        redraw()
    }

    func mouseDown(at point: CGPoint) {
        move(to: point)
        guard !windowSelection, !elementSelection else { return }
        start = point
        highlightedRect = nil
        redraw()
    }

    func mouseUp(at point: CGPoint) {
        move(to: point)
        if elementSelection {
            guard let rect = highlightedRect else { NSSound.beep(); return }
            NSLog("Smart element selected: x=%.1f y=%.1f width=%.1f height=%.1f", rect.minX, rect.minY, rect.width, rect.height)
            complete(kind: .element, rect: rect)
            return
        }
        if windowSelection, let hoveredWindow {
            complete(kind: .window(hoveredWindow.id), rect: hoveredWindow.frame)
        } else if let rect = highlightedRect, rect.width >= 1, rect.height >= 1 {
            complete(kind: .area, rect: rect)
        } else {
            start = nil
            highlightedRect = nil
            redraw()
        }
    }

    func cancel() { finish(nil) }

    func keyDown(_ event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "e":
            if !AreaSelectionAccessibility.hasPermission {
                finish(nil)
                AreaSelectionAccessibility.requestPermission()
                CaptureTextFeedbackPresenter.shared.showFailure(title: "Enable Accessibility for smart element capture", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
                return
            }
            elementSelection.toggle()
            windowSelection = false
            start = nil
            highlightedRect = nil
            NSLog("Smart element selection changed: enabled=%d", elementSelection)
            move(to: NSEvent.mouseLocation)
            return
        case "x":
            UpshotPreferences.areaSelectionCrosshair.toggle()
            NSLog("Area crosshair changed: enabled=%d", UpshotPreferences.areaSelectionCrosshair)
            redraw()
            return
        case "m":
            UpshotPreferences.areaSelectionMagnifier.toggle()
            NSLog("Area magnifier changed: enabled=%d", UpshotPreferences.areaSelectionMagnifier)
            if !frozen {
                if UpshotPreferences.areaSelectionMagnifier { startLiveMagnifier() } else { liveMagnifier.stop() }
            }
            redraw()
            return
        default: break
        }
        switch event.keyCode {
        case 53: finish(nil)
        case 49:
            elementSelection = false
            windowSelection.toggle()
            start = nil
            highlightedRect = nil
            move(to: NSEvent.mouseLocation)
        default: break
        }
    }

    private func complete(kind: AreaCaptureSelectionResult.Kind, rect: CGRect) {
        NSLog("Area selector selected: x=%.1f y=%.1f width=%.1f height=%.1f window=%d", rect.minX, rect.minY, rect.width, rect.height, windowSelection)
        let target: WindowTarget?
        if case .window(let id) = kind {
            target = windows.first { $0.id == id }
        } else {
            target = windows.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
                ?? windows.filter { $0.frame.intersects(rect) }.max {
                    let left = $0.frame.intersection(rect)
                    let right = $1.frame.intersection(rect)
                    return left.width * left.height < right.width * right.height
                }
        }
        finish(AreaCaptureSelectionResult(kind: kind, rect: rect, snapshots: snapshots, frozen: frozen, source: target?.source))
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
        if let selected { dimming.appendRect(selected.intersection(bounds)) }
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
        let text = selector.elementSelection
            ? (selector.highlightedRect == nil ? "No accessible element here · E: area · Esc: cancel" : "Click element · E: area · Esc: cancel")
            : selector.windowSelection ? "Click a window · Space: area · E: element · Esc: cancel" : "Drag across displays · Space: window · E: element · Esc: cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: (bounds.width - size.width) / 2 - 16, y: 36, width: size.width + 32, height: 36)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 16, y: rect.minY + 10), withAttributes: attributes)
    }
}
