import CoreGraphics
import Foundation

nonisolated struct AnnotationCanvasExpansion: Codable, Equatable, Sendable {
    var left: CGFloat = 0
    var top: CGFloat = 0
    var right: CGFloat = 0
    var bottom: CGFloat = 0

    var isEmpty: Bool { self == AnnotationCanvasExpansion() }
}

extension AnnotationEditorModel {
    var automaticallyExpandsCanvas: Bool {
        _ = revision
        return UpshotPreferences.annotationAutomaticallyExpandCanvas
    }

    func setAutomaticallyExpandsCanvas(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: UpshotPreferences.annotationAutomaticallyExpandCanvasKey)
        if enabled { engine.pageLimits = nil }
        updateCanvasExpansion()
        engine.notifyChanged()
        NSLog("Annotation canvas automatic expansion enabled=%@", String(enabled))
    }

    func updateCanvasExpansion() {
        guard UpshotPreferences.annotationAutomaticallyExpandCanvas,
              imageSize.width > 0, imageSize.height > 0,
              engine.editingTextId == nil,
              case .idle = engine.interaction else { return }
        var settings = backgroundSettings
        settings.canvasExpansion = AnnotationCanvasExpansion()
        let layout = AnnotationBackgroundLayout.make(contentSize: imageSize, settings: settings)
        let canvas = CGRect(x: -layout.imageRect.minX, y: -layout.imageRect.minY,
                            width: layout.canvasSize.width, height: layout.canvasSize.height)
        var bounds = canvas
        for shape in shapes {
            guard let geometry = engine.document.pageBounds(shape.id) else { continue }
            var shapeBounds = geometry.cgRect
            var strokeWidth = shape.strokeWidth
            for element in engine.document.renderElements(shape.id) {
                strokeWidth = max(strokeWidth, element.strokeWidth)
                if let path = element.cgPath {
                    shapeBounds = shapeBounds.union(path.boundingBoxOfPath.applying(shape.pageTransform.cgAffineTransform))
                }
            }
            let shadowReach: CGFloat = shape.castsShadow == true ? 22 : 0
            let margin = max(2, strokeWidth / 2) + shadowReach
            shapeBounds = shapeBounds.insetBy(dx: -margin, dy: -margin)
            guard shapeBounds.minX.isFinite, shapeBounds.minY.isFinite,
                  shapeBounds.maxX.isFinite, shapeBounds.maxY.isFinite else { continue }
            bounds = bounds.union(shapeBounds)
        }
        let expansion = AnnotationCanvasExpansion(
            left: ceil(max(0, canvas.minX - bounds.minX)),
            top: ceil(max(0, canvas.minY - bounds.minY)),
            right: ceil(max(0, bounds.maxX - canvas.maxX)),
            bottom: ceil(max(0, bounds.maxY - canvas.maxY))
        )
        guard expansion != backgroundSettings.canvasExpansion else { return }
        backgroundSettings.canvasExpansion = expansion
        NSLog("Annotation canvas expanded left=%.0f top=%.0f right=%.0f bottom=%.0f",
              expansion.left, expansion.top, expansion.right, expansion.bottom)
    }
}
