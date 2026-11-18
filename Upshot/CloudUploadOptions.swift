import AppKit
import AVKit
import Combine
import SwiftUI

struct CloudUploadOptions: Sendable {
    var title: String
    var socialEnabled: Bool
    var notes: String = ""

    var trimmedTitleOrNil: String? {
        let trimmed = String(title.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedNotesOrNil: String? {
        let trimmed = String(notes.prefix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
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
    let publishedPreviewURL: URL?
    let publishedShareURL: String?
    let allowsNotes: Bool
    let onConfirm: (CloudUploadOptions) -> Void

    @State private var title: String
    @State private var notes = ""
    @State private var copiedLink = false
    @State private var socialEnabled = CloudUploadPreferences.lastSocialEnabled
    @Environment(\.dismiss) private var dismiss

    init(suggestedTitle: String = "", publishedPreviewURL: URL? = nil, publishedShareURL: String? = nil, allowsNotes: Bool = false, onConfirm: @escaping (CloudUploadOptions) -> Void) {
        self.suggestedTitle = suggestedTitle
        self.publishedPreviewURL = publishedPreviewURL
        self.publishedShareURL = publishedShareURL
        self.allowsNotes = allowsNotes
        self.onConfirm = onConfirm
        _title = State(initialValue: String(suggestedTitle.prefix(200)))
    }

    var body: some View {
        ExportAndShareOptionsPopoverLayout(
            confirmTitle: "Upload and Copy Link",
            onCancel: { dismiss() },
            onConfirm: {
                CloudUploadPreferences.lastSocialEnabled = socialEnabled
                let options = CloudUploadOptions(title: title, socialEnabled: socialEnabled, notes: notes)
                dismiss()
                onConfirm(options)
            }
        ) {
            if let publishedPreviewURL {
                CloudPublishedVideoPreview(url: publishedPreviewURL)
            }
            if let publishedShareURL {
                HStack {
                    Text(publishedShareURL).textSelection(.enabled)
                    Button(copiedLink ? "Link copied" : "Copy link") {
                        NSPasteboard.general.clearContents()
                        copiedLink = NSPasteboard.general.setString(publishedShareURL, forType: .string)
                        AppLog.event("recording", "cloud_share_link_copied", fields: ["success": String(copiedLink)])
                    }
                    .buttonStyle(.interfaceAction)
                }
            }
            InterfaceSection(nil) {
                InterfaceTextFieldRow("Title", prompt: "Untitled", fieldWidth: 180, text: $title)
                if allowsNotes && CloudUploader.shared.acceptsNotes {
                    InterfaceTextFieldRow("Notes", prompt: "Add context, instructions, or a short summary for viewers…", fieldWidth: 180, text: $notes)
                }
                InterfaceToggleRow("Allow comments and likes", isOn: $socialEnabled)
            }
        }
        .onChange(of: title) { _, value in title = String(value.prefix(200)) }
        .onChange(of: notes) { _, value in notes = String(value.prefix(2000)) }
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

private struct CloudPublishedVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var unavailable = false

    private var statusUpdates: AnyPublisher<AVPlayerItem.Status, Never> {
        guard let item = player?.currentItem else {
            return Empty<AVPlayerItem.Status, Never>().eraseToAnyPublisher()
        }
        return item.publisher(for: \.status).receive(on: RunLoop.main).eraseToAnyPublisher()
    }

    var body: some View {
        VideoPlayer(player: player)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .accessibilityLabel("Published video preview")
            .overlay {
                if unavailable { Text("Preview unavailable. Your share link is below.") }
            }
            .onReceive(statusUpdates) { status in
                if status == .failed {
                    unavailable = true
                    AppLog.event("recording", "cloud_share_preview_failed", fields: [
                        "error": player?.currentItem?.error.map { AppLog.error($0) } ?? "unavailable"
                    ])
                }
            }
            .task(id: url) {
                unavailable = false
                player = AVPlayer(url: url)
                AppLog.event("recording", "cloud_share_preview_opened")
            }
            .onDisappear { player?.pause() }
    }
}
