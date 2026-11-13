import AppKit
import Observation

@Observable
@MainActor
final class RecordingPenPresenter {
    static let shared = RecordingPenPresenter()

    private(set) var isEnabled = false
    private(set) var hasStrokes = false
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var source: ScreenRecordingSource?
    @ObservationIgnored private var isPaused = false

    var windowIDs: Set<CGWindowID> {
        guard let panel else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    private init() {}

    static func toggleLivePen() {
        guard ScreenRecordingManager.shared.state == .recording else { return }
        shared.setEnabled(!shared.isEnabled)
    }

    static func clearLivePen() {
        guard ScreenRecordingManager.shared.state == .recording else { return }
        shared.clear()
    }

    func prepare(source: ScreenRecordingSource) {
        finish()
        self.source = source
        let rect = source.liveRecordingRect
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.sharingType = .readOnly
        let view = RecordingPenView(frame: CGRect(origin: .zero, size: rect.size))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        self.panel = panel
        panel.orderFrontRegardless()
        AppLog.event("recording", "recording_live_pen_prepared")
    }

    func updateGeometry() {
        guard let panel, let source else { return }
        let rect = source.liveRecordingRect
        guard rect != panel.frame else { return }
        RecordingPenStrokeStore.shared.end()
        panel.setFrame(rect, display: true)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        RecordingPenStrokeStore.shared.end()
        panel?.ignoresMouseEvents = paused || !isEnabled
    }

    func finish() {
        panel?.orderOut(nil)
        panel = nil
        source = nil
        isEnabled = false
        isPaused = false
        hasStrokes = false
        onChange = nil
        RecordingPenStrokeStore.shared.clear()
    }

    func strokeChanged() {
        hasStrokes = !RecordingPenStrokeStore.shared.snapshot.isEmpty
        panel?.contentView?.needsDisplay = true
        onChange?()
    }

    func strokeEnded() {
        RecordingPenStrokeStore.shared.end()
        AppLog.event("recording", "recording_live_pen_stroke_completed")
    }

    private func setEnabled(_ enabled: Bool) {
        guard panel != nil else { return }
        isEnabled = enabled
        panel?.ignoresMouseEvents = !enabled || isPaused
        if !enabled { RecordingPenStrokeStore.shared.end() }
        panel?.resetCursorRects()
        AppLog.event("recording", "recording_live_pen", fields: ["enabled": String(enabled)])
    }

    private func clear() {
        RecordingPenStrokeStore.shared.clear()
        strokeChanged()
        AppLog.event("recording", "recording_live_pen_cleared")
    }
}

final class RecordingPenView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        if RecordingPenPresenter.shared.isEnabled {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        RecordingPenRenderer.draw(RecordingPenStrokeStore.shared.snapshot, in: context, rect: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        guard RecordingPenPresenter.shared.isEnabled, ScreenRecordingManager.shared.state == .recording else { return }
        RecordingPenStrokeStore.shared.begin(at: normalizedPoint(event), lineWidth: 4 / max(1, bounds.height))
        RecordingPenPresenter.shared.strokeChanged()
    }

    override func mouseDragged(with event: NSEvent) {
        guard RecordingPenPresenter.shared.isEnabled, ScreenRecordingManager.shared.state == .recording else { return }
        RecordingPenStrokeStore.shared.append(normalizedPoint(event))
        RecordingPenPresenter.shared.strokeChanged()
    }

    override func mouseUp(with event: NSEvent) {
        guard RecordingPenPresenter.shared.isEnabled, ScreenRecordingManager.shared.state == .recording else { return }
        RecordingPenStrokeStore.shared.append(normalizedPoint(event))
        RecordingPenPresenter.shared.strokeChanged()
        RecordingPenPresenter.shared.strokeEnded()
    }

    private func normalizedPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x / max(1, bounds.width), 0), 1),
                       y: min(max(point.y / max(1, bounds.height), 0), 1))
    }
}
