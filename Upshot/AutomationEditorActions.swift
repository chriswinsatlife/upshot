import AppKit

enum AutomationEditorActions {
    private struct Registration {
        weak var window: NSWindow?
        let isEnabled: () -> Bool
        let handlers: [CaptureHotkeyAction: () -> Void]
    }

    private static var registrations: [ObjectIdentifier: Registration] = [:]
    private static var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func register(window: NSWindow, isEnabled: @escaping () -> Bool, handlers: [CaptureHotkeyAction: () -> Void]) {
        let identifier = ObjectIdentifier(window)
        unregister(window: window)
        registrations[identifier] = Registration(window: window, isEnabled: isEnabled, handlers: handlers)
        closeObservers[identifier] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { removeRegistration(identifier) }
        }
    }

    static func unregister(window: NSWindow) {
        removeRegistration(ObjectIdentifier(window))
    }

    private static func removeRegistration(_ identifier: ObjectIdentifier) {
        registrations.removeValue(forKey: identifier)
        if let observer = closeObservers.removeValue(forKey: identifier) {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    static func perform(_ action: CaptureHotkeyAction) throws {
        guard let registration = NSApp.orderedWindows.lazy.compactMap({ window in
            window.isVisible && !window.isMiniaturized ? registrations[ObjectIdentifier(window)] : nil
        }).first else {
            throw AutomationError.message("Open a screenshot editor with automation actions registered before using this action.")
        }
        guard registration.isEnabled() else { throw AutomationError.message("The screenshot editor is busy.") }
        guard let handler = registration.handlers[action] else { throw AutomationError.message("This screenshot editor action requires editor integration.") }
        handler()
    }
}
