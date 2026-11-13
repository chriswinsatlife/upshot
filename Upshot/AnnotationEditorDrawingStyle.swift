import Foundation

extension AnnotationEditorModel {
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
