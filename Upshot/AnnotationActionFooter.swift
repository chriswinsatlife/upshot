import SwiftUI

struct AnnotationActionFooter: View {
    let canShare: Bool
    let isUploading: Bool
    let didCopyLink: Bool
    let isFinishing: Bool
    let isBusy: Bool
    let suggestedTitle: String
    let onUpload: (CloudUploadOptions) -> Void
    let onSaveAs: () -> Void
    let onDone: () -> Void

    static let height: CGFloat = InterfaceMetrics.controlHeight + Space.ml * 2

    @State private var isShareOptionsPresented = false

    var body: some View {
        HStack(spacing: Space.m) {
            if canShare {
                Button {
                    isShareOptionsPresented = true
                } label: {
                    Label(shareTitle, systemImage: shareSystemImage)
                        .contentTransition(.symbolEffect(.replace))
                }
                .disabled(isBusy)
                .help(isUploading ? "Uploading…" : "Share a link")
                .popover(isPresented: $isShareOptionsPresented, arrowEdge: .top) {
                    CloudUploadOptionsPopover(suggestedTitle: suggestedTitle, onConfirm: onUpload)
                }
            }

            Button(action: onSaveAs) {
                Text("Save As…")
            }
            .disabled(isBusy)
            .help("Save a Copy As…")

            Spacer(minLength: Space.m)

            Button(action: onDone) {
                Text(isFinishing ? "Saving…" : "Done")
            }
            .disabled(isBusy)
            .help("Save and close")
        }
        .buttonStyle(.interfaceAction)
        .padding(.horizontal, Space.l)
        .frame(height: Self.height)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .motion(.morphQuick, value: didCopyLink)
    }

    private var shareTitle: String {
        if didCopyLink { return "Link Copied" }
        return isUploading ? "Uploading…" : "Share"
    }

    private var shareSystemImage: String {
        if didCopyLink { return "checkmark" }
        return isUploading ? "arrow.up.circle" : "link"
    }
}
