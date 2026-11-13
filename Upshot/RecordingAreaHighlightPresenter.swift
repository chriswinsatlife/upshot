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
        NSLog("[Upshot] Recording dimming started on \(panels.count) displays")
    }

    func update() {
        guard let source else { return }
        if screenFrames != NSScreen.screens.map(\.frame) {
            rebuildPanels()
        }
        let recordingRect = source.liveRecordingRect
        for panel in panels {
            guard let view = panel.contentView as? RecordingAreaHighlightView else { continue }
            view.highlightRect = recordingRect.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            view.needsDisplay = true
        }
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
            NSLog("[Upshot] Recording dimming stopped")
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
            panel.sharingType = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.contentView = RecordingAreaHighlightView(frame: CGRect(origin: .zero, size: frame.size))
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
               let rect = CGRect(dictionaryRepresentation: bounds) {
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

private final class RecordingAreaHighlightView: NSView {
    var highlightRect: CGRect = .zero

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()
        NSColor.clear.setFill()
        highlightRect.intersection(bounds).fill(using: .clear)
    }
}
