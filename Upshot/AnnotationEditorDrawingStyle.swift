import Foundation

extension AnnotationEditorModel {
    var objectShadowsEnabled: Bool {
        _ = revision
        return engine.selectedShapes.first?.castsShadow ?? UpshotPreferences.annotationObjectShadows
    }

    func setObjectShadows(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: UpshotPreferences.annotationObjectShadowsKey)
        engine.applyStyleToSelection { $0.castsShadow = enabled }
        engine.notifyChanged()
        NSLog("Annotation object shadows applied enabled=%@ selected=%ld", String(enabled), engine.selectedIds.count)
    }

    var drawingSmoothing: Double {
        _ = revision
        return engine.selectedShapes.first?.drawProps?.smoothing ?? UpshotPreferences.annotationDrawingSmoothing
    }

    func setDrawingSmoothing(_ value: Double) {
        let smoothing = min(1, max(0, value))
        UserDefaults.standard.set(smoothing, forKey: UpshotPreferences.annotationDrawingSmoothingKey)
        engine.applyStyleToSelection { shape in
            guard case var .draw(props) = shape.kind else { return }
            props.smoothing = smoothing
            shape.kind = .draw(props)
        }
        engine.notifyChanged()
        NSLog("Annotation freehand smoothing applied value=%.2f", smoothing)
    }
}
