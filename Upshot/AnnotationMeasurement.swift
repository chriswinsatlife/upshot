import AppKit
import CoreGraphics
import Foundation

enum AnnotationMeasurement {
    static func distance(_ properties: ArrowProps) -> Double {
        Vec.dist(properties.start, properties.end)
    }

    static func geometry(_ properties: ArrowProps) -> Geometry2d {
        let labelPaths = elements(properties).dropFirst().compactMap(\.cgPath)
        let labelBounds = labelPaths.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
        let edge = Edge2d(start: properties.start, end: properties.end)
        guard !labelBounds.isNull else { return edge }
        let box = Box(labelBounds.minX, labelBounds.minY, labelBounds.width, labelBounds.height)
        return Group2d(children: [edge, Polygon2d(points: box.corners, isFilled: true)])
    }

    static func elements(_ properties: ArrowProps) -> [RenderElement] {
        let start = properties.start
        let end = properties.end
        let delta = Vec.sub(end, start)
        guard delta.len > 0 else { return [] }
        let normal = delta.uni.per
        let tick = max(6, properties.strokeWidth * 2)
        let path = CGMutablePath()
        path.move(to: start.cgPoint)
        path.addLine(to: end.cgPoint)
        for terminal in [start, end] {
            path.move(to: Vec.sub(terminal, Vec.mul(normal, tick)).cgPoint)
            path.addLine(to: Vec.add(terminal, Vec.mul(normal, tick)).cgPoint)
        }
        var label = TextProps()
        label.text = String(format: "%.1f px", distance(properties))
        label.fontSize = max(16, properties.strokeWidth * 4)
        label.style = .label
        label.swatch = properties.swatch
        let size = AnnotationTextDecoration.size(label)
        let midpoint = Vec.med(start, end)
        let transform = CGAffineTransform(translationX: midpoint.x - size.width / 2, y: midpoint.y - size.height / 2)
        let labelElements = AnnotationTextDecoration.elements(label).compactMap { element -> RenderElement? in
            guard let path = element.cgPath else { return nil }
            var element = element
            var transform = transform
            guard let translated = path.copy(using: &transform) else { return nil }
            element.content = .path(translated)
            return element
        }
        return [RenderElement(content: .path(path), stroke: properties.swatch.nsColor, strokeWidth: properties.strokeWidth)] + labelElements
    }
}
