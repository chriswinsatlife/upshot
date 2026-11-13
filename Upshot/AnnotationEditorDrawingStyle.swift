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
        NSLog("Annotation redaction style applied style=%@", kind.rawValue)
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
        NSLog("Annotation object shadows applied enabled=%@ selected=%ld", String(enabled), engine.selectedIds.count)
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
        NSLog("Annotation freehand smoothing applied value=%.2f", smoothing)
    }
}
