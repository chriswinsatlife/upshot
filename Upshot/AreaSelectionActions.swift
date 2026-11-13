import AppKit

enum AreaSelectionActions {
    static func capturePreviousArea() {
        CaptureCoordinator.shared.capturePreviousArea()
    }
}
