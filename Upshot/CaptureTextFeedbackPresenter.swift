import AppKit
import SwiftUI

@MainActor
final class CaptureTextFeedbackPresenter {
    static let shared = CaptureTextFeedbackPresenter()

    private static let toastSize = NSSize(width: 300, height: 52)
    private static let shadowSlack: CGFloat = 24
    private static var panelSize: NSSize {
        NSSize(width: toastSize.width + 2 * shadowSlack, height: toastSize.height + 2 * shadowSlack)
    }
    private static let bottomInset: CGFloat = 96
    private static let visibleDuration: Duration = .seconds(1.8)
    private static let fadeOutDuration: TimeInterval = 0.2

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func showCopied(text: String, displayID: CGDirectDisplayID?) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let title = lines.count == 1
            ? "Copied 1 line"
            : "Copied \(lines.count) lines"
        present(
            symbol: "text.viewfinder",
            title: title,
            detail: lines.first.map(String.init) ?? text,
            displayID: displayID
        )
    }

    func showNoTextFound(displayID: CGDirectDisplayID?) {
        present(
            symbol: "text.viewfinder",
            title: "No text found",
            detail: "Nothing was recognized in that area.",
            displayID: displayID
        )
    }

    func showFailure(title: String, displayID: CGDirectDisplayID?) {
        NSLog("Text recognition feedback presented: %@", title)
        let detail = switch title {
        case "Capture failed": "The screenshot could not be captured or read."
        case "Text recognition failed": "The capture succeeded, but text recognition failed."
        case "Code recognition failed": "The capture succeeded, but code recognition failed."
        default: "Try again."
        }
        present(
            symbol: "exclamationmark.triangle",
            title: title,
            detail: detail,
            displayID: displayID
        )
    }

    private func present(
        symbol: String,
        title: String,
        detail: String,
        displayID: CGDirectDisplayID?
    ) {
        dismissTask?.cancel()
        dismiss()

        let size = Self.panelSize
        let hostingView = NSHostingView(
            rootView: CaptureTextFeedbackView(
                symbol: symbol,
                title: title,
                detail: detail,
                size: Self.toastSize
            )
            .padding(Self.shadowSlack)
        )
        hostingView.sizingOptions = []

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hostingView
        panel.setFrame(
            NSRect(origin: origin(size: size, displayID: displayID), size: size),
            display: true
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        PreviewWindowCaptureExclusion.shared.register(window: panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            await self?.fadeOutAndDismiss()
        }
    }

    private func fadeOutAndDismiss() async {
        guard let panel else { return }

        await NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        }

        guard self.panel === panel else { return }
        dismiss()
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func origin(size: NSSize, displayID: CGDirectDisplayID?) -> CGPoint {
        let screen = screen(for: displayID) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        return CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + Self.bottomInset - Self.shadowSlack
        )
    }

    private func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
    }
}

struct CaptureTextFeedbackView: View {
    let symbol: String
    let title: String
    let detail: String
    let size: NSSize

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.label)
                .frame(width: 30, height: 30)
                .background(Palette.fill, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dsHeadline)
                    .foregroundStyle(Palette.label)
                Text(detail)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(width: size.width, height: size.height)
        .glassHUD(radius: size.height / 2)
    }
}
