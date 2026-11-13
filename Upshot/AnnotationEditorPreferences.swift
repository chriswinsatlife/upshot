import Foundation

extension UpshotPreferences {
    static let annotationAutomaticallyExpandCanvasKey = "annotationEditor.automaticallyExpandCanvas"

    static var annotationAutomaticallyExpandCanvas: Bool {
        UpshotStorage.defaults.object(forKey: annotationAutomaticallyExpandCanvasKey) as? Bool ?? false
    }

    static let annotationObjectShadowsKey = "annotationEditor.objectShadows"

    static var annotationObjectShadows: Bool {
        UpshotStorage.defaults.bool(forKey: annotationObjectShadowsKey)
    }

    static let annotationDrawingSmoothingKey = "annotationEditor.drawingSmoothing"

    static var annotationDrawingSmoothing: Double {
        min(1, max(0, UpshotStorage.defaults.object(forKey: annotationDrawingSmoothingKey) as? Double ?? 0.62))
    }

    static let annotationEditorAlwaysOnTopKey = "annotationEditor.alwaysOnTop"

    static var annotationEditorAlwaysOnTop: Bool {
        UpshotStorage.defaults.bool(forKey: annotationEditorAlwaysOnTopKey)
    }
}
