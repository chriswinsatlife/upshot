import AppKit

@MainActor
enum FailureAlert {
    enum Operation {
        case saveCapture
        case copyRecording
        case saveRecording
        case saveRecordingProject

        var title: String {
            switch self {
            case .saveCapture: "Couldn\u{2019}t Save Capture"
            case .copyRecording: "Couldn\u{2019}t Copy Recording"
            case .saveRecording: "Couldn\u{2019}t Save Recording"
            case .saveRecordingProject: "Couldn\u{2019}t Save Recording Project"
            }
        }

        var detail: String? {
            switch self {
            case .saveCapture: nil
            case .copyRecording, .saveRecording: "The recording stays safe in its project."
            case .saveRecordingProject: "The editor stays open so you can save again."
            }
        }
    }

    static func alert(for operation: Operation, error: Error) -> AppAlert {
        AppAlerts.operationFailed(title: operation.title, error: error, detail: operation.detail)
    }

    static func present(_ operation: Operation, error: Error) {
        guard !(error is CancellationError) else { return }
        alert(for: operation, error: error).runModal()
    }

    static func present(message: String, error: Error, detail: String? = nil) {
        guard !(error is CancellationError) else { return }
        AppAlerts.operationFailed(title: message, error: error, detail: detail).runModal()
    }
}
