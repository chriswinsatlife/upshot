import AppKit
import SwiftUI

struct CloudUploadOptions: Sendable {
    var title: String
    var socialEnabled: Bool

    var trimmedTitleOrNil: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CloudUploadPreferences {
    private static let socialEnabledKey = "cloudUploadDefaultSocialEnabled"

    static var lastSocialEnabled: Bool {
        get {
            guard UpshotStorage.defaults.object(forKey: socialEnabledKey) != nil else {
                return true
            }
            return UpshotStorage.defaults.bool(forKey: socialEnabledKey)
        }
        set { UpshotStorage.defaults.set(newValue, forKey: socialEnabledKey) }
    }
}

struct CloudUploadOptionsPopover: View {
    let suggestedTitle: String
    let onConfirm: (CloudUploadOptions) -> Void

    @State private var title: String
    @State private var socialEnabled = CloudUploadPreferences.lastSocialEnabled
    @Environment(\.dismiss) private var dismiss

    init(suggestedTitle: String = "", onConfirm: @escaping (CloudUploadOptions) -> Void) {
        self.suggestedTitle = suggestedTitle
        self.onConfirm = onConfirm
        _title = State(initialValue: suggestedTitle)
    }

    var body: some View {
        ExportAndShareOptionsPopoverLayout(
            confirmTitle: "Upload and Copy Link",
            onCancel: { dismiss() },
            onConfirm: {
                CloudUploadPreferences.lastSocialEnabled = socialEnabled
                let options = CloudUploadOptions(title: title, socialEnabled: socialEnabled)
                dismiss()
                onConfirm(options)
            }
        ) {
            InterfaceSection(nil) {
                InterfaceTextFieldRow("Title", prompt: "Untitled", fieldWidth: 180, text: $title)
                InterfaceToggleRow("Allow comments and likes", isOn: $socialEnabled)
            }
        }
        .background(CloudUploadOptionsInitialFocusClearance())
    }
}

private struct CloudUploadOptionsInitialFocusClearance: NSViewRepresentable {
    func makeNSView(context: Context) -> CloudUploadOptionsInitialFocusClearanceView {
        CloudUploadOptionsInitialFocusClearanceView()
    }

    func updateNSView(_ nsView: CloudUploadOptionsInitialFocusClearanceView, context: Context) {}
}

private final class CloudUploadOptionsInitialFocusClearanceView: NSView {
    private var keyWindowObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
        guard let window else { return }
        window.initialFirstResponder = nil
        DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                (notification.object as? NSWindow)?.makeFirstResponder(nil)
                if let observer = self?.keyWindowObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self?.keyWindowObserver = nil
                }
            }
        }
    }
}

struct CloudUploadButton<Label: View>: View {
    let suggestedTitle: String
    let onUpload: (CloudUploadOptions) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showingOptions = false

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            label()
        }
        .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
            CloudUploadOptionsPopover(suggestedTitle: suggestedTitle, onConfirm: onUpload)
        }
    }
}
