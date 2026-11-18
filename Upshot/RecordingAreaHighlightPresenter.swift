import AppKit
import ScreenCaptureKit

@MainActor
final class RecordingAreaHighlightPresenter {
    static let shared = RecordingAreaHighlightPresenter()

    private var panels: [NSPanel] = []
    private var source: ScreenRecordingSource?
    private var screenFrames: [CGRect] = []
    private var screenDisplayIDs: [CGDirectDisplayID] = []
    private var refreshTimer: Timer?
    private var areaRectInDisplay: CGRect?

    var windowIDs: Set<CGWindowID> {
        Set(panels.map { CGWindowID($0.windowNumber) })
    }

    private init() {}

    func show(display: SCDisplay, rect: CGRect) {
        show(source: ScreenRecordingSource(kind: .area(display: display, rect: rect)))
    }

    func show(source: ScreenRecordingSource) {
        hide()
        guard UpshotPreferences.recordingDimOutsideArea else { return }
        self.source = source
        if case .area(let display, let rect) = source.kind,
           let screen = ActiveDisplayResolver.screen(for: display.displayID) {
            areaRectInDisplay = rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        }
        rebuildPanels()
        update()
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { RecordingAreaHighlightPresenter.shared.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        AppLog.event("recording", "recording_dimming_started", fields: ["displays": String(describing: panels.count)])
    }

    @discardableResult
    func update() -> Bool {
        guard let source else { return true }
        if screenFrames != NSScreen.screens.map(\.frame)
            || screenDisplayIDs != NSScreen.screens.compactMap({ ActiveDisplayResolver.displayID(for: $0) }) {
            AppLog.event("recording", "recording_dimming_detected_a_display_configuration_change")
            rebuildPanels()
        }
        let recordingRect: CGRect
        if case .area(let display, _) = source.kind,
           let areaRectInDisplay,
           let screen = ActiveDisplayResolver.screen(for: display.displayID) {
            recordingRect = areaRectInDisplay.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY).integral
        } else {
            recordingRect = source.liveRecordingRect.integral
        }
        let barRect = RecordingBarPresenter.shared.barFrame?.insetBy(dx: -8, dy: -8).integral
        for panel in panels {
            guard let view = panel.contentView as? RecordingAreaHighlightView else { continue }
            view.highlightRect = recordingRect.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            view.barRect = barRect?.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            if case .area = source.kind {
                view.showsAreaBorder = true
            } else {
                view.showsAreaBorder = false
            }
            view.needsDisplay = true
        }
        return true
    }

    func hide() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let wasVisible = !panels.isEmpty
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        screenFrames.removeAll()
        screenDisplayIDs.removeAll()
        areaRectInDisplay = nil
        source = nil
        if wasVisible {
            AppLog.event("recording", "recording_dimming_stopped")
        }
    }

    private func rebuildPanels() {
        let previousPanels = Dictionary(uniqueKeysWithValues: zip(screenDisplayIDs, panels))
        screenFrames = NSScreen.screens.map(\.frame)
        screenDisplayIDs = NSScreen.screens.compactMap { ActiveDisplayResolver.displayID(for: $0) }
        for (displayID, panel) in previousPanels where !screenDisplayIDs.contains(displayID) {
            panel.orderOut(nil)
        }
        panels = NSScreen.screens.compactMap { screen in
            guard let displayID = ActiveDisplayResolver.displayID(for: screen) else { return nil }
            let frame = screen.frame
            if let panel = previousPanels[displayID] {
                panel.setFrame(frame, display: false)
                panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
                return panel
            }
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.level = .screenSaver
            panel.ignoresMouseEvents = true
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            let view = RecordingAreaHighlightView(frame: CGRect(origin: .zero, size: frame.size))
            view.highlightRect = source?.liveRecordingRect.offsetBy(dx: -frame.minX, dy: -frame.minY) ?? .zero
            panel.contentView = view
            panel.orderFrontRegardless()
            return panel
        }
    }
}

extension ScreenRecordingSource {
    var liveRecordingRect: CGRect {
        switch kind {
        case .fullscreen(let display):
            return ActiveDisplayResolver.screen(for: display.displayID)?.frame ?? Self.appKitRect(display.frame)
        case .area(_, let rect):
            return rect
        case .window(let window):
            let information = CGWindowListCopyWindowInfo(.optionIncludingWindow, window.windowID) as? [[String: Any]]
            if let bounds = information?.first?[kCGWindowBounds as String] as? NSDictionary,
               let rect = CaptureRectangleDecoder.decode(bounds) {
                return Self.appKitRect(rect)
            }
            return Self.appKitRect(window.frame)
        }
    }

    private static func appKitRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: CGDisplayBounds(CGMainDisplayID()).height - rect.maxY,
               width: rect.width, height: rect.height)
    }
}

final class RecordingAreaHighlightView: NSView {
    static let screenDimmingColor = NSColor.black.withAlphaComponent(0.32)
    private static let recordingDimmingColor = NSColor.black.withAlphaComponent(0.38)

    var highlightRect: CGRect = .zero
    var barRect: CGRect?
    var showsAreaBorder = false

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        Self.recordingDimmingColor.setFill()
        bounds.fill()
        NSColor.clear.setFill()
        let visibleRecordingRect = highlightRect.intersection(bounds)
        if !visibleRecordingRect.isEmpty {
            visibleRecordingRect.fill(using: .clear)
        }
        if showsAreaBorder, !visibleRecordingRect.isEmpty {
            let border = NSBezierPath(rect: highlightRect.insetBy(dx: -1, dy: -1))
            NSColor.black.withAlphaComponent(0.45).setStroke()
            border.lineWidth = 4
            border.stroke()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            border.lineWidth = 2
            let dash: [CGFloat] = [6, 6]
            border.setLineDash(dash, count: dash.count, phase: 0)
            border.stroke()
            visibleRecordingRect.fill(using: .clear)
        }
        if let barRect {
            let visibleBarRect = barRect.intersection(bounds)
            if !visibleBarRect.isEmpty {
                visibleBarRect.fill(using: .clear)
            }
        }
    }
}
