import AppKit
import SwiftUI
import Vision

@MainActor
final class CaptureCodeFeedbackPresenter {
    static let shared = CaptureCodeFeedbackPresenter()

    private static let bottomInset: CGFloat = 166
    private static let maximumListHeight: CGFloat = 320
    private static let screenMargin: CGFloat = 20

    private var panel: NSPanel?

    private init() {}

    func present(_ detection: CaptureCodeDetection, displayID: CGDirectDisplayID?) {
        panel?.close()
        panel = nil
        guard !detection.isEmpty else { return }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let panel = CaptureCodePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let listHeight = Self.listHeight(visibleFrame: frame)
        let hostingView = NSHostingView(
            rootView: CaptureCodeFeedbackView(detection: detection, maximumListHeight: listHeight) { [weak panel] in
                panel?.close()
            }
        )
        hostingView.sizingOptions = []
        let size = hostingView.fittingSize

        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.setFrame(NSRect(origin: Self.origin(size: size, visibleFrame: frame), size: size), display: true)
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        self.panel = panel
        AppLog.event("capture", "capture_code_prompt_presented", fields: ["codes": String(describing: detection.codes.count), "links": String(describing: detection.links.count)])
    }
}

extension CaptureCodeFeedbackPresenter {
    static func listHeight(visibleFrame frame: CGRect) -> CGFloat {
        min(maximumListHeight, frame.height - 200)
    }

    static func origin(size: NSSize, visibleFrame frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.midX - size.width / 2,
            y: min(frame.minY + bottomInset, frame.maxY - size.height - screenMargin)
        )
    }
}

private final class CaptureCodePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private enum CaptureCodeFeedbackItem: Identifiable {
    case code(DetectedCaptureCode, link: URL?)
    case link(URL)

    var id: String {
        switch self {
        case .code(let code, _): "code:" + code.id
        case .link(let link): "link:" + link.absoluteString
        }
    }

    static func items(for detection: CaptureCodeDetection) -> [CaptureCodeFeedbackItem] {
        var remainingLinks = detection.links
        let codeItems = detection.codes.map { code -> CaptureCodeFeedbackItem in
            guard let payload = code.payload,
                  let index = remainingLinks.firstIndex(where: { $0.absoluteString == payload }) else {
                return .code(code, link: nil)
            }
            return .code(code, link: remainingLinks.remove(at: index))
        }
        return codeItems + remainingLinks.map(CaptureCodeFeedbackItem.link)
    }
}

struct CaptureCodeFeedbackView: View {
    let detection: CaptureCodeDetection
    var maximumListHeight: CGFloat = 320
    let dismiss: () -> Void
    @State private var copied: Set<String>
    @State private var failure: String?

    private static let panelWidth: CGFloat = 440

    init(
        detection: CaptureCodeDetection,
        maximumListHeight: CGFloat = 320,
        copiedIdentifiers: Set<String> = [],
        failure: String? = nil,
        dismiss: @escaping () -> Void
    ) {
        self.detection = detection
        self.maximumListHeight = maximumListHeight
        self.dismiss = dismiss
        self._copied = State(initialValue: copiedIdentifiers)
        self._failure = State(initialValue: failure)
    }

    var body: some View {
        InterfacePanel(.flyout, padding: InterfaceMetrics.flyoutPadding) {
            HStack(alignment: .top, spacing: Space.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(CaptureCodeFeedbackItem.items(for: detection)) { item in
                                row(for: item)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: maximumListHeight)
                    .fixedSize(horizontal: false, vertical: true)
                    if let failure {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.dsCaption)
                            .foregroundStyle(Palette.destructiveLabel)
                            .padding(.horizontal, Space.m)
                            .padding(.vertical, Space.s)
                    }
                }
                InterfaceToolbarDivider()
                InterfaceToolbarButton("Close", systemImage: "xmark", labelPlacement: .hidden, action: dismiss)
                    .keyboardShortcut(.cancelAction)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.panelWidth)
        .onExitCommand(perform: dismiss)
    }

    @ViewBuilder
    private func row(for item: CaptureCodeFeedbackItem) -> some View {
        switch item {
        case .code(let code, let link):
            CaptureCodeFeedbackRow(
                title: code.title,
                systemImage: code.symbology == VNBarcodeSymbology.qr.rawValue ? "qrcode" : "barcode",
                payload: code.displayPayload,
                payloadEncoding: code.payload == nil ? "Base64" : nil,
                isCopied: copied.contains(code.id),
                copy: { copy(code) },
                open: link.map { link in { open(link) } }
            )
        case .link(let link):
            CaptureCodeFeedbackRow(
                title: "Link",
                systemImage: "link",
                payload: link.absoluteString,
                isCopied: copied.contains(link.absoluteString),
                copy: { copy(link) },
                open: { open(link) }
            )
        }
    }

    private func copy(_ code: DetectedCaptureCode) {
        let item = NSPasteboardItem()
        item.setString(code.displayPayload, forType: .string)
        if let data = code.data {
            item.setData(data, forType: NSPasteboard.PasteboardType("public.data"))
        }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([item]) {
            copied.insert(code.id)
            failure = nil
            AppLog.event("capture", "capture_code_payload_copied", fields: ["symbology": String(describing: code.symbology)])
        } else {
            failure = "The payload could not be copied."
            AppLog.event("capture", "capture_code_payload_copy_failed")
        }
    }

    private func copy(_ link: URL) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(link.absoluteString, forType: .string) {
            copied.insert(link.absoluteString)
            failure = nil
            AppLog.event("capture", "capture_detected_link_copied")
        } else {
            failure = "The link could not be copied."
            AppLog.event("capture", "capture_detected_link_copy_failed")
        }
    }

    private func open(_ link: URL) {
        if NSWorkspace.shared.open(link) {
            failure = nil
            AppLog.event("capture", "capture_detected_link_opened_after_confirmation")
        } else {
            failure = "The link could not be opened."
            AppLog.event("capture", "capture_detected_link_open_failed")
        }
    }
}

private struct CaptureCodeFeedbackRow: View {
    let title: String
    let systemImage: String
    let payload: String
    var payloadEncoding: String? = nil
    let isCopied: Bool
    let copy: () -> Void
    let open: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.ml) {
            Image(systemName: systemImage)
                .font(.system(size: IconSize.flyout, weight: .medium))
                .foregroundStyle(Palette.label)
                .frame(width: InterfaceMetrics.flyoutIconSlotWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: InterfaceMetrics.rowLabelToDetailSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(title)
                        .font(.dsBodyEmphasis)
                        .foregroundStyle(Palette.label)
                    if let payloadEncoding {
                        Text(payloadEncoding)
                            .font(.dsCaption)
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                }
                Text(payload)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.xxs) {
                if let open {
                    InterfaceToolbarButton("Open Link", systemImage: "arrow.up.forward.square", labelPlacement: .hidden, action: open)
                }
                InterfaceToolbarButton(
                    isCopied ? "Copied" : "Copy",
                    systemImage: isCopied ? "checkmark" : "doc.on.doc",
                    labelPlacement: .hidden,
                    tint: isCopied ? Palette.success : nil,
                    action: copy
                )
                .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.leading, Space.m)
        .padding(.vertical, Space.xs)
    }
}
