import AppKit

enum AreaSelectionActions {
    static func toggleCrosshair() {
        AreaCaptureSelection.shared.toggleCrosshair()
    }

    static func toggleMagnifier() {
        AreaCaptureSelection.shared.toggleMagnifier()
    }

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
