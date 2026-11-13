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
                NSLog("Capture text clipboard write failed")
                return
            }
            NSLog("Capture text clipboard write completed")
            CaptureTextFeedbackPresenter.shared.showCopied(text: text, displayID: displayID)
        } catch is CancellationError {
            return
        } catch {
            NSLog("Capture text %@: %@", ImageTextRecognizer.failureTitle(for: error), String(describing: error))
            CaptureTextFeedbackPresenter.shared.showFailure(title: ImageTextRecognizer.failureTitle(for: error), displayID: displayID)
        }
    }
}
