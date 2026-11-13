import AppKit

enum AreaSelectionActions {
    static func captureSmartElement() {
        CaptureCoordinator.shared.captureSmartElement()
    }

    static func capturePreviousArea() {
        CaptureCoordinator.shared.capturePreviousArea()
    }
}
