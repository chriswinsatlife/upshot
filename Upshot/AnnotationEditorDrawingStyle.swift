import Foundation

extension AnnotationEditorModel {
    var redactionKind: RedactionKind {
        _ = revision
        return engine.selectedShapes.first?.redactionProps?.kind ?? (selectedTool == .pixelate ? .pixelate : engine.currentRedactionKind)
    }

    func setRedactionKind(_ kind: RedactionKind) {
        engine.currentRedactionKind = kind == .pixelate ? .blur : kind
        if engine.selectedIds.isEmpty {
            selectTool(kind == .pixelate ? .pixelate : .blur)
        }
        engine.applyStyleToSelection { shape in
            guard case var .redaction(props) = shape.kind else { return }
            props.kind = kind
            shape.kind = .redaction(props)
        }
        engine.notifyChanged()
        AppLog.event("annotation", "annotation_redaction_style_applied", fields: ["style": String(describing: kind.rawValue)])
    }

    var objectShadowsEnabled: Bool {
        _ = revision
        if let shape = engine.selectedShapes.first { return shape.castsShadow ?? false }
        return UpshotPreferences.annotationObjectShadows
    }

    func setObjectShadows(_ enabled: Bool) {
        UpshotStorage.defaults.set(enabled, forKey: UpshotPreferences.annotationObjectShadowsKey)
        engine.applyStyleToSelection { $0.castsShadow = enabled }
        engine.notifyChanged()
        AppLog.event("annotation", "annotation_object_shadows_applied", fields: ["enabled": String(describing: String(enabled)), "selected": String(describing: engine.selectedIds.count)])
    }

    var drawingSmoothing: Double {
        _ = revision
        if let properties = engine.selectedShapes.first?.drawProps { return properties.smoothing ?? 0.62 }
        return UpshotPreferences.annotationDrawingSmoothing
    }

    func setDrawingSmoothing(_ value: Double) {
        let smoothing = min(1, max(0, value))
        UpshotStorage.defaults.set(smoothing, forKey: UpshotPreferences.annotationDrawingSmoothingKey)
        engine.applyStyleToSelection { shape in
            guard case var .draw(props) = shape.kind else { return }
            props.smoothing = smoothing
            shape.kind = .draw(props)
        }
        engine.notifyChanged()
        AppLog.event("annotation", "annotation_freehand_smoothing_applied", fields: ["value": String(describing: smoothing)])
    }
}
