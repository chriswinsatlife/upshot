import Foundation

@MainActor
enum AnnotationEditorAction {
    case selectTool(AnnotationTool)
    case setTextStyle(AnnotationTextStyle)
    case setRedactionStyle(RedactionKind)
    case setWatermark(AnnotationWatermarkSettings)
    case combineImage(URL, AnnotationImageCombination)
    case setColorAdjustments(AnnotationColorAdjustments)
    case transformImage(AnnotationImageTransform)
    case setDrawingSmoothing(Double)
    case setObjectShadows(Bool)
    case setAutomaticallyExpandsCanvas(Bool)
    case setAlwaysOnTop(Bool)

    static func perform(_ action: AnnotationEditorAction, on model: AnnotationEditorModel) async {
        switch action {
        case let .selectTool(tool):
            model.selectTool(tool)
        case let .setTextStyle(style):
            model.selectedTextStyle = style
        case let .setRedactionStyle(style):
            model.setRedactionKind(style)
        case let .setWatermark(settings):
            model.backgroundSettings.watermark = settings
            AppLog.event("annotation", "annotation_watermark_changed", fields: ["opacity": String(describing: settings.opacity), "position": String(describing: settings.position.rawValue)])
        case let .combineImage(url, layout):
            await model.combineImage(at: url, layout: layout)
        case let .setColorAdjustments(settings):
            model.backgroundSettings.colorAdjustments = settings
            await model.updateColorPreview()
        case let .transformImage(operation):
            await model.transformImage(operation)
        case let .setDrawingSmoothing(value):
            model.setDrawingSmoothing(value)
        case let .setObjectShadows(enabled):
            model.setObjectShadows(enabled)
        case let .setAutomaticallyExpandsCanvas(enabled):
            model.setAutomaticallyExpandsCanvas(enabled)
        case let .setAlwaysOnTop(enabled):
            UpshotStorage.defaults.set(enabled, forKey: UpshotPreferences.annotationEditorAlwaysOnTopKey)
            AppLog.event("annotation", "annotation_always_on_top_preference_changed", fields: ["enabled": String(describing: String(enabled))])
        }
    }
}
