import Foundation

final class AnnoDocument {
    private(set) var shapes: [AnnoShape] = []
    private(set) var bindings: [ArrowBinding] = []

    private var indexById: [AnnoShapeID: Int] = [:]
    private var geometryCache: [AnnoShapeID: Geometry2d] = [:]
    private var arrowInfoCache: [AnnoShapeID: ArrowInfo] = [:]
    private var renderCache: [AnnoShapeID: [RenderElement]] = [:]


    func shape(_ id: AnnoShapeID) -> AnnoShape? {
        guard let i = indexById[id] else { return nil }
        return shapes[i]
    }

    func index(of id: AnnoShapeID) -> Int? { indexById[id] }

    func pageTransform(_ shape: AnnoShape) -> Mat { shape.pageTransform }

    func pageTransform(_ id: AnnoShapeID) -> Mat? { shape(id)?.pageTransform }

    func pointInShapeSpace(_ shape: AnnoShape, _ pagePoint: Vec) -> Vec {
        shape.pageTransform.inverse.applyToPoint(pagePoint)
    }

    func geometry(_ id: AnnoShapeID) -> Geometry2d? {
        if let cached = geometryCache[id] { return cached }
        guard let shape = shape(id) else { return nil }
        let geometry = AnnoShapeGeometry.build(shape, in: self)
        geometryCache[id] = geometry
        return geometry
    }

    func geometry(_ shape: AnnoShape) -> Geometry2d {
        geometry(shape.id) ?? AnnoShapeGeometry.build(shape, in: self)
    }

    func pageBounds(_ id: AnnoShapeID) -> Box? {
        guard let shape = shape(id), let geometry = geometry(id) else { return nil }
        return Box.fromPoints(shape.pageTransform.applyToPoints(geometry.vertices))
    }

    func pageCorners(_ id: AnnoShapeID) -> [Vec]? {
        guard let shape = shape(id), let geometry = geometry(id) else { return nil }
        return shape.pageTransform.applyToPoints(geometry.bounds.corners)
    }


    func arrowInfo(_ id: AnnoShapeID) -> ArrowInfo? {
        if let cached = arrowInfoCache[id] { return cached }
        guard let shape = shape(id), case .arrow = shape.kind else { return nil }
        let info = ArrowEngine.getArrowInfo(self, shape)
        arrowInfoCache[id] = info
        return info
    }

    func renderElements(_ id: AnnoShapeID) -> [RenderElement] {
        if let cached = renderCache[id] { return cached }
        guard let shape = shape(id) else { return [] }
        let elements = AnnoShapeRenderer.elements(for: shape, in: self)
        renderCache[id] = elements
        return elements
    }

    func arrowBindings(_ arrowId: AnnoShapeID) -> ArrowBindings {
        ArrowBindings(
            start: bindings.first { $0.arrowId == arrowId && $0.terminal == .start },
            end: bindings.first { $0.arrowId == arrowId && $0.terminal == .end }
        )
    }

    func bindings(from arrowId: AnnoShapeID) -> [ArrowBinding] {
        bindings.filter { $0.arrowId == arrowId }
    }

    func bindings(to shapeId: AnnoShapeID) -> [ArrowBinding] {
        bindings.filter { $0.toId == shapeId }
    }


    private func invalidate(_ ids: Set<AnnoShapeID>) {
        var stale = ids
        for binding in bindings where ids.contains(binding.toId) {
            stale.insert(binding.arrowId)
        }
        for id in stale {
            geometryCache.removeValue(forKey: id)
            arrowInfoCache.removeValue(forKey: id)
            renderCache.removeValue(forKey: id)
        }
    }

    private func invalidateAll() {
        geometryCache.removeAll(keepingCapacity: true)
        arrowInfoCache.removeAll(keepingCapacity: true)
        renderCache.removeAll(keepingCapacity: true)
    }

    private func reindex() {
        indexById.removeAll(keepingCapacity: true)
        for (i, shape) in shapes.enumerated() { indexById[shape.id] = i }
    }

    func add(_ shape: AnnoShape) {
        shapes.append(shape)
        reindex()
        invalidate([shape.id])
    }

    func update(_ shape: AnnoShape) {
        guard let i = indexById[shape.id] else { return }
        shapes[i] = shape
        invalidate([shape.id])
    }

    func update(_ id: AnnoShapeID, _ transform: (inout AnnoShape) -> Void) {
        guard let i = indexById[id] else { return }
        transform(&shapes[i])
        invalidate([id])
    }

    func delete(_ ids: Set<AnnoShapeID>) {
        shapes.removeAll { ids.contains($0.id) }
        let stale = ids.union(bindings.filter { ids.contains($0.toId) }.map(\.arrowId))
        bindings.removeAll { ids.contains($0.arrowId) || ids.contains($0.toId) }
        reindex()
        invalidate(stale)
    }

    func bringToFront(_ ids: Set<AnnoShapeID>) {
        let moved = shapes.filter { ids.contains($0.id) }
        shapes.removeAll { ids.contains($0.id) }
        shapes.append(contentsOf: moved)
        reindex()
    }

    func sendToBack(_ ids: Set<AnnoShapeID>) {
        let moved = shapes.filter { ids.contains($0.id) }
        shapes.removeAll { ids.contains($0.id) }
        shapes.insert(contentsOf: moved, at: 0)
        reindex()
    }

    func setBinding(_ binding: ArrowBinding) {
        bindings.removeAll { $0.arrowId == binding.arrowId && $0.terminal == binding.terminal }
        bindings.append(binding)
        invalidate([binding.arrowId])
    }

    func removeBinding(arrowId: AnnoShapeID, terminal: ArrowTerminal) {
        bindings.removeAll { $0.arrowId == arrowId && $0.terminal == terminal }
        invalidate([arrowId])
    }


    struct Snapshot: Codable {
        var shapes: [AnnoShape]
        var bindings: [ArrowBinding]
    }

    func snapshot() -> Snapshot {
        Snapshot(shapes: shapes, bindings: bindings)
    }

    func restore(_ snapshot: Snapshot) {
        shapes = snapshot.shapes
        bindings = snapshot.bindings
        reindex()
        invalidateAll()
    }
}

enum AnnoShapeGeometry {
    static func build(_ shape: AnnoShape, in document: AnnoDocument) -> Geometry2d {
        switch shape.kind {
        case let .draw(props):
            return drawGeometry(props)
        case let .geo(props):
            let isFilled = props.fill != .none
            switch props.geo {
            case .rectangle:
                guard props.cornerRadius > 0.5 else {
                    return Rectangle2d(width: props.w, height: props.h, isFilled: isFilled)
                }
                let vertices = GeoPaths.path(for: props).vertices()
                guard vertices.count >= 3 else {
                    return Rectangle2d(width: props.w, height: props.h, isFilled: isFilled)
                }
                return Polygon2d(points: vertices, isFilled: isFilled)
            case .ellipse:
                return Ellipse2d(width: props.w, height: props.h, isFilled: isFilled)
            }
        case .arrow:
            return arrowGeometry(shape, in: document)
        case let .text(props):
            let size = AnnotationTextDecoration.size(props)
            return Rectangle2d(
                width: Double(size.width),
                height: Double(size.height),
                isFilled: true
            )
        case let .redaction(props):
            return Rectangle2d(width: props.w, height: props.h, isFilled: true)
        case let .highlight(props):
            return Rectangle2d(width: props.w, height: props.h, isFilled: true)
        case let .numbered(props):
            return Ellipse2d(width: props.diameter, height: props.diameter, isFilled: true)
        }
    }

    private static func drawGeometry(_ props: DrawProps) -> Geometry2d {
        let points = props.points
        let sw = props.strokeWidth + 1

        guard !points.isEmpty else {
            return Circle2d(x: -sw, y: -sw, radius: sw, isFilled: true)
        }

        let box = Box.fromPoints(points)
        if box.width < sw * 2 && box.height < sw * 2 {
            return Circle2d(x: -sw, y: -sw, radius: sw, isFilled: true)
        }

        let options = FreehandSettings.forDrawShape(
            isPen: props.isPen,
            isComplete: props.isComplete,
            strokeWidth: sw,
            forceComplete: true,
            forceSolid: true,
            smoothing: props.smoothing
        )
        let strokePoints = StrokeOutline.getStrokePoints(points, options).map { $0.point }

        if props.isClosed && strokePoints.count > 2 {
            return Polygon2d(points: strokePoints, isFilled: false)
        }
        if strokePoints.count < 2 {
            return Circle2d(x: -sw, y: -sw, radius: sw, isFilled: true)
        }
        return Polyline2d(points: strokePoints)
    }

    private static func arrowGeometry(_ shape: AnnoShape, in document: AnnoDocument) -> Geometry2d {
        guard let info = ArrowEngine.getArrowInfo(document, shape) else {
            return Polyline2d(points: [Vec(0, 0), Vec(1, 1)])
        }
        switch info.body {
        case let .straight(start, end):
            if Vec.equals(start, end) {
                return Polyline2d(points: [start, Vec.addXY(end, 1, 1)])
            }
            return Edge2d(start: start, end: end)
        case let .arc(arc):
            guard arc.radius.isFinite, arc.radius > 0, !Vec.equals(info.start.point, info.end.point) else {
                return Edge2d(start: info.start.point, end: info.end.point)
            }
            return Arc2d(
                center: arc.center,
                start: info.start.point,
                end: info.end.point,
                sweepFlag: arc.sweepFlag,
                largeArcFlag: arc.largeArcFlag
            )
        }
    }
}
