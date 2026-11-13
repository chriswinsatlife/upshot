import Foundation

extension UpshotPreferences {
    static let annotationInverseArrowDirectionKey = "annotationEditor.inverseArrowDirection"

    static var annotationInverseArrowDirection: Bool {
        UpshotStorage.defaults.bool(forKey: annotationInverseArrowDirectionKey)
    }

    static func annotationArrowDirectionIsInverted(optionHeld: Bool) -> Bool {
        optionHeld != annotationInverseArrowDirection
    }

    static let annotationShowColorNamesKey = "annotationEditor.showColorNames"

    static var annotationShowColorNames: Bool {
        UpshotStorage.defaults.object(forKey: annotationShowColorNamesKey) as? Bool ?? true
    }

    static let annotationDefaultDrawingSmoothing = 0.62
}
