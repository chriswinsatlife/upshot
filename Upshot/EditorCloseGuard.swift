import AppKit

@MainActor
final class EditorCloseGuard: NSObject, NSWindowDelegate {
    enum Decision {
        case save
        case discard
        case delete
        case cancel
    }

    var hasUnsavedChanges: () -> Bool = { false }
    var canClose: () -> Bool = { true }
    var offersDelete: () -> Bool = { false }
    var projectName: () -> String = { "" }
    var onDecision: (Decision, @escaping () -> Void) -> Void = { _, done in done() }

    private weak var attachedWindow: NSWindow?
    private nonisolated(unsafe) weak var previousDelegate: NSWindowDelegate?
    private var isPrompting = false
    private var isCloseApproved = false

    func attach(to window: NSWindow?) {
        guard let window else {
            detach()
            return
        }
        guard window !== attachedWindow else { return }
        detachFromWindow()
        isPrompting = false
        isCloseApproved = false
        attachedWindow = window
        previousDelegate = window.delegate
        window.delegate = self
    }

    func detach() {
        detachFromWindow()
        hasUnsavedChanges = { false }
        canClose = { true }
        offersDelete = { false }
        projectName = { "" }
        onDecision = { _, done in done() }
        isPrompting = false
        isCloseApproved = false
    }

    private func detachFromWindow() {
        if let attachedWindow, attachedWindow.delegate === self {
            attachedWindow.delegate = previousDelegate
        }
        attachedWindow = nil
        previousDelegate = nil
    }

    func refreshDocumentEdited() {
        attachedWindow?.isDocumentEdited = hasUnsavedChanges()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard canClose() else { return false }
        if isCloseApproved { return true }
        guard hasUnsavedChanges() else { return true }
        guard !isPrompting else { return false }

        isPrompting = true
        present(on: sender)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        let delegate = previousDelegate
        detach()
        delegate?.windowWillClose?(notification)
    }

    static func alert(offersDelete: Bool, projectName: String) -> AppAlert {
        offersDelete
            ? AppAlerts.editorUnsavedNewRecording(projectName: projectName)
            : AppAlerts.editorUnsavedChanges(projectName: projectName)
    }

    private func present(on window: NSWindow) {
        Self.alert(offersDelete: offersDelete(), projectName: projectName()).beginSheet(for: window) { [weak self, weak window] action in
            guard let self else { return }
            self.isPrompting = false

            let decision: Decision
            switch action {
            case .save:
                decision = .save
            case .doNotSave:
                decision = .discard
            case .deleteRecording:
                decision = .delete
            default:
                decision = .cancel
            }

            guard decision != .cancel else { return }

            self.onDecision(decision) { [weak self, weak window] in
                guard let self, let window else { return }
                self.isCloseApproved = true
                window.close()
            }
        }
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previousDelegate?.responds(to: aSelector) ?? false
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        previousDelegate
    }
}
