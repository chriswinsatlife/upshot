import Foundation

extension UpshotPreferences {
    static let annotationDrawingSmoothingKey = "annotationEditor.drawingSmoothing"

    static var annotationDrawingSmoothing: Double {
        min(1, max(0, UserDefaults.standard.object(forKey: annotationDrawingSmoothingKey) as? Double ?? 0.62))
    }

    static let annotationEditorAlwaysOnTopKey = "annotationEditor.alwaysOnTop"

    static var annotationEditorAlwaysOnTop: Bool {
        UserDefaults.standard.bool(forKey: annotationEditorAlwaysOnTopKey)
    }
}
