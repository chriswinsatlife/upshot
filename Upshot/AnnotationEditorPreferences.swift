import Foundation

extension UpshotPreferences {
    static let annotationEditorAlwaysOnTopKey = "annotationEditor.alwaysOnTop"

    static var annotationEditorAlwaysOnTop: Bool {
        UserDefaults.standard.bool(forKey: annotationEditorAlwaysOnTopKey)
    }
}
