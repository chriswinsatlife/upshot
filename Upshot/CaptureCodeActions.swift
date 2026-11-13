import AppKit

@MainActor
enum CaptureCodeActions {
    static func detectCodes(at url: URL, displayID: CGDirectDisplayID? = nil) async {
        do {
            let image = try await ImageTextRecognizer.loadImage(at: url)
            let codes = try await CaptureCodeRecognizer.detect(in: image)
            let detection = try CaptureCodeRecognizer.detection(codes: codes, text: "", detectLinks: UpshotPreferences.recognitionDetectLinks)
            CaptureCodeFeedbackPresenter.shared.present(detection, displayID: displayID)
        } catch is CancellationError {
            return
        } catch {
            AppLog.event("capture", "capture_code_detection_failed", fields: ["error": AppLog.error(error)])
            CaptureTextFeedbackPresenter.shared.showFailure(
                title: error is TextRecognitionError ? ImageTextRecognizer.failureTitle(for: error) : "Code recognition failed",
                displayID: displayID
            )
        }
    }
}
