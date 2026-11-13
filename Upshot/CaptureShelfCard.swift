import AppKit
import SwiftUI

struct CaptureShelfCard: View {
    let item: ShelfItem
    let shelf: CaptureShelf

    @State private var isHovered = UpshotStorage.isRenderingStates && StateRenderer.scenario.contains("hover")
    @State private var layoutStore = OverlayCardLayoutStore.shared
    @State private var uploader = CloudUploader.shared
    @AppStorage(UpshotPreferences.previewOverlaySizeKey) private var overlaySize = QuickAccessOverlaySize.small

    private var cardSize: CGSize {
        CGSize(width: 168 * overlaySize.scale, height: 118 * overlaySize.scale)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CaptureShelfMetrics.cardRadius, style: .continuous)
    }

    var body: some View {
        InterfaceCard(padding: 0) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: cardSize.width, height: cardSize.height)
                .blur(radius: isFrosted ? 6 : 0, opaque: true)
                .overlay { overlay }
        }
        .opacity(isDragging ? 0.35 : 1)
        .contentShape(shape)
        .onHover { hovering in
            isHovered = hovering
            shelf.setHovered(item.id, hovering)
        }
        .motion(.morphQuick, value: showsActions)
        .motion(.morphQuick, value: item.flash)
        .motion(.morphQuick, value: item.activity)
        .simultaneousGesture(TapGesture(count: 2).onEnded { shelf.openEditor(id: item.id) })
        .draggable(item.url) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: cardSize.width)
                .clipShape(shape)
        }
        .onDragSessionUpdated { session in
            switch session.phase {
            case .active: shelf.beginDrag(id: item.id)
            case .ended(let operation): shelf.endDrag(id: item.id, operation: operation)
            default: break
            }
        }
        .contextMenu { contextMenu }
        .help("\(item.kind == .video ? "Double-click to edit" : "Double-click to annotate") · C copy · S save · E edit · P pin screenshot · Delete close · Option-drag to keep")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.kind == .video ? "Recording" : "Screenshot")
    }

    private var isDragging: Bool { shelf.draggingID == item.id }
    private var isUploading: Bool { uploader.uploadingItems.contains(item.id) }
    private var uploadedLink: String? { uploader.uploadedURLs[item.id] }
    private var showsActions: Bool { isHovered && !isDragging && !shelf.isMoving }
    private var isFrosted: Bool {
        showsActions || item.activity != nil || isUploading || item.flash != nil
    }

    @ViewBuilder
    private var overlay: some View {
        if let activity = item.activity {
            CaptureShelfActivityPanel(title: activity == .compressing ? "Compressing" : "Preparing")
                .transition(AnyTransition(.blurReplace))
        } else if isUploading {
            CaptureShelfUploadPanel(progress: uploader.uploadProgress[item.id] ?? 0) {
                uploader.cancelUpload(for: item.id)
            }
            .padding(Space.m)
            .transition(AnyTransition(.blurReplace))
        } else if let flash = item.flash {
            flashToast(flash)
                .padding(Space.m)
                .transition(AnyTransition(.blurReplace))
        } else if showsActions {
            actions
                .transition(.opacity)
        } else if item.kind == .video {
            Image(systemName: "play.fill")
                .font(.system(size: IconSize.segment, weight: .semibold))
                .foregroundStyle(Palette.label)
                .frame(width: InterfaceMetrics.controlHeight, height: InterfaceMetrics.controlHeight)
                .interfacePanelSurface(.pill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(Space.s)
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func flashToast(_ flash: ShelfFlash) -> some View {
        switch flash {
        case .linkCopied:
            CaptureShelfFlashToast(title: "Link Copied", systemImage: "checkmark.circle.fill", tone: .success)
        case .uploadFailed:
            CaptureShelfFlashToast(title: "Upload Failed", systemImage: "exclamationmark.triangle.fill", tone: .failure)
        case .compressed(let summary):
            CaptureShelfFlashToast(title: "JPG Copied", detail: summary, systemImage: "checkmark.circle.fill", tone: .success)
        case .actionFailed(let message):
            CaptureShelfFlashToast(title: message, systemImage: "exclamationmark.triangle.fill", tone: .failure)
        }
    }

    private var actions: some View {
        let layout = layoutStore.layout
        return ZStack {
            corner(layout.topLeading, .topLeading)
            corner(layout.topTrailing, .topTrailing)
            corner(layout.bottomLeading, .bottomLeading)
            corner(layout.bottomTrailing, .bottomTrailing)

            VStack(spacing: Space.s) {
                ForEach(layout.center.filter(isAvailable)) { action in
                    CaptureShelfCardButton(help: centerHelp(for: action), shape: .capsule) {
                        perform(action)
                    } label: {
                        Text(centerTitle(for: action))
                            .font(.dsBodyEmphasis)
                            .lineLimit(1)
                    }
                    .disabled(isBlocked(action))
                }
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func corner(_ action: OverlayCardAction?, _ alignment: Alignment) -> some View {
        if let action, isAvailable(action) {
            CaptureShelfCardButton(help: cornerHelp(for: action), shape: .circle) {
                perform(action)
            } label: {
                Image(systemName: cornerSymbol(for: action))
                    .font(.system(size: IconSize.actionButton, weight: .semibold))
            }
            .disabled(isBlocked(action))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(Space.s)
        }
    }

    private func isAvailable(_ action: OverlayCardAction) -> Bool {
        switch action {
        case .pin, .compress: item.kind == .image
        case .upload: uploader.isConfigured
        default: true
        }
    }

    private func cornerSymbol(for action: OverlayCardAction) -> String {
        action == .upload && uploadedLink != nil ? "link" : action.symbol(for: item.kind)
    }

    private func cornerHelp(for action: OverlayCardAction) -> String {
        if isBlocked(action) { return Self.deleteBlockedHelp }
        return action == .upload && uploadedLink != nil ? "Copy share link" : action.help(for: item.kind)
    }

    private func centerHelp(for action: OverlayCardAction) -> String {
        isBlocked(action) ? Self.deleteBlockedHelp : action.help(for: item.kind)
    }

    private func isBlocked(_ action: OverlayCardAction) -> Bool {
        action == .delete && shelf.isOpenInEditor(id: item.id)
    }

    private static let deleteBlockedHelp = "Close its editor to delete it"

    private func centerTitle(for action: OverlayCardAction) -> String {
        action == .upload && uploadedLink != nil ? "Copy Link" : action.label(for: item.kind)
    }

    private func perform(_ action: OverlayCardAction) {
        shelf.perform(action, id: item.id)
    }

    @ViewBuilder
    private var contextMenu: some View {
        let id = item.id
        let isImage = item.kind == .image

        Button(isImage ? "Annotate" : "Edit Recording") { shelf.openEditor(id: id) }
        Button("Quick Look") { shelf.quickLook(id: id) }

        Divider()

        Button("Copy") { shelf.copy(id: id) }
        if isImage {
            Button("Copy Text from Image") { shelf.copyText(id: id) }
            Button("Copy as Compressed JPG") { shelf.compress(id: id) }
        }
        Button("Save") { shelf.save(id: id) }
        Button("Save As…") { shelf.save(id: id, choosingLocation: true) }
        if isImage {
            Button("Pin to Screen") { shelf.pin(id: id) }
        }
        if uploader.isConfigured {
            if uploadedLink != nil {
                Button("Copy Share Link") { shelf.copyLink(id: id) }
            } else {
                Button("Upload and Copy Link") { shelf.upload(id: id) }
            }
        }

        Divider()

        Button("Dismiss") { shelf.dismiss(id: id) }
        Button(isImage ? "Delete Screenshot" : "Delete Recording", role: .destructive) {
            shelf.delete(id: id)
        }
        .disabled(shelf.isOpenInEditor(id: id))
    }
}

private enum CaptureShelfCardButtonShape {
    case circle
    case capsule
}

private struct CaptureShelfCardButton<Label: View>: View {
    let help: String
    let shape: CaptureShelfCardButtonShape
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @Environment(\.isEnabled) private var isEnabled

    private static var height: CGFloat { InterfaceMetrics.modeSwitchHeight - Space.xxs * 2 }

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
                .padding(.horizontal, shape == .capsule ? Space.l : 0)
                .frame(width: shape == .circle ? Self.height : nil, height: Self.height)
                .frame(maxWidth: shape == .capsule ? .infinity : nil)
        }
        .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.pill))
        .interfacePanelSurface(.pill)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct CaptureShelfFlashToast: View {
    let title: String
    var detail: String? = nil
    let systemImage: String
    let tone: InterfaceToastTone

    var body: some View {
        ViewThatFits(in: .horizontal) {
            InterfaceToast(title, detail: detail, systemImage: systemImage, tone: tone)
            InterfacePanel(.flyout, padding: Space.l) {
                VStack(spacing: Space.s) {
                    Image(systemName: systemImage)
                        .font(.system(size: IconSize.toast, weight: .semibold))
                        .foregroundStyle(tone.color)
                    Text(title)
                        .font(.dsBodyEmphasis)
                        .foregroundStyle(Palette.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(.dsCaption)
                            .foregroundStyle(Palette.secondaryLabel)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct CaptureShelfActivityPanel: View {
    let title: String

    var body: some View {
        HStack(spacing: Space.ml) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.dsBodyEmphasis)
                .foregroundStyle(Palette.label)
                .lineLimit(1)
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.xl)
        .padding(.vertical, Space.s)
        .frame(minHeight: InterfaceMetrics.toastMinimumHeight)
        .fixedSize()
        .interfacePanelSurface(.flyout)
        .accessibilityElement(children: .combine)
    }
}

private struct CaptureShelfUploadPanel: View {
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Uploading")
                    .font(.dsBodyEmphasis)
                    .foregroundStyle(Palette.label)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: IconSize.actionButton, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .frame(width: InterfaceMetrics.modeSwitchHeight, height: InterfaceMetrics.modeSwitchHeight)
            }
            .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.pill))
            .help("Cancel upload")
            .accessibilityLabel("Cancel upload")
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.s)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity)
        .interfacePanelSurface(.flyout)
    }
}
