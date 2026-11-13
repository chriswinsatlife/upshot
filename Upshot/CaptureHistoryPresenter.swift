import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class CaptureHistoryPresenter: NSObject, NSWindowDelegate {
    static let shared = CaptureHistoryPresenter()

    private var panel: CaptureHistoryPanel?
    private var model: CaptureHistoryModel?
    private var targetDisplayID: CGDirectDisplayID?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    private override init() { super.init() }

    func show() {
        targetDisplayID = ActiveDisplayResolver.activeDisplayID()
        if panel == nil { makePanel() }
        applyPlacement()
        model?.refresh()
        panel?.makeKeyAndOrderFront(nil)
        AppLog.event("library", "capture_history_opened", fields: ["display": String(describing: targetDisplayID ?? 0)])
    }

    func dismiss() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        model?.stop()
        model = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        keyMonitor = nil
        screenObserver = nil
        AppLog.event("library", "capture_history_closed")
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    private func makePanel() {
        let model = CaptureHistoryModel()
        let panel = CaptureHistoryPanel(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 280),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Capture History"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.delegate = self
        let hostingView = CaptureHistoryHostingView(rootView: CaptureHistoryView(model: model))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        self.panel = panel
        self.model = model
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow, event.window === panel else { return event }
            return self.handleKey(event) ? nil : event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPlacement() }
        }
    }

    private func applyPlacement() {
        guard let panel,
              let screen = ActiveDisplayResolver.screen(for: targetDisplayID) ?? ActiveDisplayResolver.activeScreen() else { return }
        let visible = screen.visibleFrame
        let height = min(280, visible.height)
        panel.setFrame(CGRect(x: screen.frame.minX, y: visible.maxY - height, width: screen.frame.width, height: height), display: panel.isVisible)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 53: dismiss()
        case 123: model.moveSelection(by: -1)
        case 124: model.moveSelection(by: 1)
        case 115: model.selectBoundary(last: false)
        case 119: model.selectBoundary(last: true)
        case 36, 76: model.restoreSelection()
        case 48: model.moveFilter(by: modifiers.contains(.shift) ? -1 : 1)
        default: return false
        }
        return true
    }
}

private final class CaptureHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CaptureHistoryHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
