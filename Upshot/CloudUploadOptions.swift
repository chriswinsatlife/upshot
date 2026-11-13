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
        InspectorPopover(
            title: "Share Options",
            message: "Uploads to your cloud and copies a share link.",
            confirmTitle: "Upload",
            onCancel: { dismiss() },
            onConfirm: {
                CloudUploadPreferences.lastSocialEnabled = socialEnabled
                let options = CloudUploadOptions(title: title, socialEnabled: socialEnabled)
                dismiss()
                onConfirm(options)
            }
        ) {
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
                    InspectorGroupLabel("Title")
                    TextField("Title", text: $title, prompt: Text("Untitled"))
                        .labelsHidden()
                        .lineLimit(1)
                        .inspectorTextField()
                }

                InspectorToggleRow("Allow comments & likes", isOn: $socialEnabled)
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
