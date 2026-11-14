import AppKit

final class LiveStateAlertWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var isKeyWindow: Bool { true }
    @objc var hasKeyAppearance: Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

@MainActor
final class LiveStateAlertButtonTarget: NSObject {
    private var alert: NSAlert?
    private let buttonPressed: (@MainActor (NSApplication.ModalResponse) -> Void)?

    init(alert: NSAlert, buttonPressed: (@MainActor (NSApplication.ModalResponse) -> Void)?) {
        self.alert = alert
        self.buttonPressed = buttonPressed
        super.init()
        for button in alert.buttons {
            button.target = self
            button.action = #selector(press(_:))
        }
    }

    @objc func press(_ sender: NSButton) {
        guard let index = alert?.buttons.firstIndex(of: sender) else { return }
        let response = NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index)
        let window = sender.window
        window?.orderOut(nil)
        LiveStateLog.event("alert_button_pressed", ["button": sender.title, "response": response.rawValue, "windowNumber": window?.windowNumber ?? 0,
                                                    "alertRemoved": window.map { !$0.isVisible } ?? false])
        buttonPressed?(response)
    }

    func release() {
        for button in alert?.buttons ?? [] where button.target === self {
            button.target = nil
            button.action = nil
        }
        alert = nil
    }
}

extension LiveStatePresentation {
    static let modalAlertPanelStyleBits: UInt = 1 << 36 | 1 << 20
    static let alertRegionMargin: CGFloat = 40

    public init(alert: NSAlert, over context: NSWindow? = nil, settleDuration: Duration = .milliseconds(100),
                buttonPressed: (@MainActor (NSApplication.ModalResponse) -> Void)? = nil, tearDown: (@MainActor () -> Void)? = nil) {
        alert.layout()
        let source = alert.window
        let content = source.contentView
        let styleMask = NSWindow.StyleMask(rawValue: source.styleMask.rawValue & ~Self.modalAlertPanelStyleBits)
        let window = LiveStateAlertWindow(contentRect: source.frame, styleMask: styleMask, backing: .buffered, defer: false)
        window.titleVisibility = source.titleVisibility
        window.titlebarAppearsTransparent = source.titlebarAppearsTransparent
        window.isOpaque = source.isOpaque
        window.backgroundColor = source.backgroundColor
        window.hasShadow = true
        source.contentView = nil
        window.contentView = content
        window.setFrame(source.frame, display: false)
        if let context {
            let size = window.frame.size
            let parent = context.frame
            let titlebar = parent.height - context.contentLayoutRect.height
            window.setFrameOrigin(CGPoint(x: (parent.midX - size.width / 2).rounded(), y: (parent.maxY - titlebar - 24 - size.height).rounded()))
        } else if let display = LiveStateWindowPlacement.mainDisplayFrame {
            window.setFrameOrigin(CGPoint(x: (display.midX - window.frame.width / 2).rounded(), y: (display.midY - window.frame.height / 2).rounded()))
        }
        let target = LiveStateAlertButtonTarget(alert: alert, buttonPressed: buttonPressed)
        LiveStateLog.event("alert_rehosted", [
            "messageText": alert.messageText, "buttons": alert.buttons.map(\.title), "sourceClass": String(describing: type(of: source)),
            "sourceStyleMask": Int(source.styleMask.rawValue), "styleMask": Int(window.styleMask.rawValue),
            "width": Double(window.frame.width), "height": Double(window.frame.height),
        ])
        let release: @MainActor () -> Void = {
            target.release()
            tearDown?()
        }
        if let context {
            self.init(regionWindows: [context, window], settleDuration: settleDuration, tearDown: release)
        } else {
            self.init(regionWindows: [window], regionFrame: window.frame.insetBy(dx: -Self.alertRegionMargin, dy: -Self.alertRegionMargin),
                      settleDuration: settleDuration, tearDown: release)
        }
        modalWindow = window
    }
}
