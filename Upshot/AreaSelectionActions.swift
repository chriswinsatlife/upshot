import AppKit

enum AreaSelectionActions {
    static func captureAllInOne() {
        CaptureCoordinator.shared.captureAllInOne()
    }

    static func captureSmartElement() {
        CaptureCoordinator.shared.captureSmartElement()
    }

    static func capturePreviousArea() {
        CaptureCoordinator.shared.capturePreviousArea()
    }
}
