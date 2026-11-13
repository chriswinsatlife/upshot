import AppKit
import ScreenCaptureKit

@MainActor
final class RecordingAreaHighlightPresenter {
    static let shared = RecordingAreaHighlightPresenter()

    private var panels: [NSPanel] = []
    private var source: ScreenRecordingSource?
    private var screenFrames: [CGRect] = []

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
        rebuildPanels()
        update()
        AppLog.event("recording", "recording_dimming_started", fields: ["displays": String(describing: panels.count)])
    }

    @discardableResult
    func update() -> Bool {
        guard let source else { return true }
        if screenFrames != NSScreen.screens.map(\.frame) {
            AppLog.event("recording", "recording_dimming_detected_a_display_configuration_change")
            return false
        }
        let recordingRect = source.liveRecordingRect
        for panel in panels {
            guard let view = panel.contentView as? RecordingAreaHighlightView else { continue }
            view.highlightRect = recordingRect.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            view.needsDisplay = true
        }
        return true
    }

    func hide() {
        let wasVisible = !panels.isEmpty
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        screenFrames.removeAll()
        source = nil
        if wasVisible {
            AppLog.event("recording", "recording_dimming_stopped")
        }
    }

    private func rebuildPanels() {
        for panel in panels {
            panel.orderOut(nil)
        }
        screenFrames = NSScreen.screens.map(\.frame)
        panels = screenFrames.map { frame in
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
            panel.sharingType = .readOnly
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

    var highlightRect: CGRect = .zero

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        Self.screenDimmingColor.setFill()
        bounds.fill()
        NSColor.clear.setFill()
        let visibleRecordingRect = highlightRect.intersection(bounds)
        if !visibleRecordingRect.isEmpty {
            visibleRecordingRect.fill(using: .clear)
        }
    }
}
