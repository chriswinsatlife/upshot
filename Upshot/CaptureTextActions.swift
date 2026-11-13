import AppKit

@MainActor
enum CaptureTextActions {
    static func copyText(at url: URL, displayID: CGDirectDisplayID? = nil) async {
        do {
            let text = try await ImageTextRecognizer.recognizeCaptureText(at: url)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                CaptureTextFeedbackPresenter.shared.showNoTextFound(displayID: displayID)
                return
            }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else {
                CaptureTextFeedbackPresenter.shared.showFailure(title: "Copy failed", displayID: displayID)
                AppLog.event("capture", "capture_text_clipboard_write_failed")
                return
            }
            AppLog.event("capture", "capture_text_clipboard_write_completed")
            CaptureTextFeedbackPresenter.shared.showCopied(text: text, displayID: displayID)
        } catch is CancellationError {
            return
        } catch {
            AppLog.event("capture", "capture_text", fields: ["error": AppLog.error(error), "failure": ImageTextRecognizer.failureTitle(for: error)])
            CaptureTextFeedbackPresenter.shared.showFailure(title: ImageTextRecognizer.failureTitle(for: error), displayID: displayID)
        }
    }
}
