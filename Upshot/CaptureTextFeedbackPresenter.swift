import AppKit
import SwiftUI

struct CaptureTextFeedback: Equatable {
    let title: String
    var detail: String? = nil
    let systemImage: String
    var tone: InterfaceToastTone = .neutral

    private static let maximumDetailCharacterCount = 56

    static func copied(text: String) -> CaptureTextFeedback {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let firstLine = lines.first ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        return CaptureTextFeedback(
            title: lines.count == 1 ? "Copied 1 line" : "Copied \(lines.count) lines",
            detail: abbreviatedDetail(firstLine),
            systemImage: "checkmark.circle.fill",
            tone: .success
        )
    }

    static let noTextFound = CaptureTextFeedback(title: "No text found", systemImage: "text.viewfinder")

    static func failure(title: String) -> CaptureTextFeedback {
        CaptureTextFeedback(title: title, systemImage: "exclamationmark.triangle.fill", tone: .failure)
    }

    private static func abbreviatedDetail(_ line: String) -> String? {
        guard !line.isEmpty else { return nil }
        guard line.count > maximumDetailCharacterCount else { return line }
        return String(line.prefix(maximumDetailCharacterCount - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

@MainActor
final class CaptureTextFeedbackPresenter {
    static let shared = CaptureTextFeedbackPresenter()

    private static let shadowSlack: CGFloat = 24
    private static let bottomInset: CGFloat = 96
    private static let entranceRise: CGFloat = 8
    private static let visibleDuration: Duration = .seconds(1.8)
    private static let fadeInDuration: TimeInterval = 0.2
    private static let fadeOutDuration: TimeInterval = 0.15
    private static let entranceTimingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func showCopied(text: String, displayID: CGDirectDisplayID?) {
        AppLog.event("capture", "text_recognition_feedback_presented", fields: ["outcome": "copied"])
        present(.copied(text: text), displayID: displayID)
    }

    func showNoTextFound(displayID: CGDirectDisplayID?) {
        AppLog.event("capture", "text_recognition_feedback_presented", fields: ["outcome": "no_text_found"])
        present(.noTextFound, displayID: displayID)
    }

    func showFailure(title: String, displayID: CGDirectDisplayID?) {
        AppLog.event("capture", "text_recognition_feedback_presented", fields: ["outcome": "failure", "title": title])
        present(.failure(title: title), displayID: displayID)
    }

    private func present(_ feedback: CaptureTextFeedback, displayID: CGDirectDisplayID?) {
        dismissTask?.cancel()
        dismiss()

        let hostingView = NSHostingView(
            rootView: CaptureTextFeedbackView(feedback: feedback)
                .padding(Self.shadowSlack)
        )
        hostingView.sizingOptions = []
        let size = hostingView.fittingSize

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

        let restingFrame = NSRect(origin: origin(size: size, displayID: displayID), size: size)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(restingFrame.offsetBy(dx: 0, dy: reduceMotion ? 0 : -Self.entranceRise), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        PreviewWindowCaptureExclusion.shared.register(window: panel)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            context.timingFunction = Self.entranceTimingFunction
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrame(restingFrame, display: true)
            }
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
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
    let feedback: CaptureTextFeedback

    var body: some View {
        InterfaceToast(
            feedback.title,
            detail: feedback.detail,
            systemImage: feedback.systemImage,
            tone: feedback.tone
        )
    }
}
