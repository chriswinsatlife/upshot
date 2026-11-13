import AppKit
import Foundation


enum AnnoSelectionHandle: Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case rotate(corner: Int)
    case arrowStart, arrowMiddle, arrowEnd

    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomRight, .bottomLeft: true
        default: false
        }
    }

    var isRotate: Bool {
        if case .rotate = self { return true }
        return false
    }

    var anchor: Vec? {
        switch self {
        case .topLeft: Vec(1, 1)
        case .top: Vec(0.5, 1)
        case .topRight: Vec(0, 1)
        case .right: Vec(0, 0.5)
        case .bottomRight: Vec(0, 0)
        case .bottom: Vec(0.5, 0)
        case .bottomLeft: Vec(1, 0)
        case .left: Vec(1, 0.5)
        default: nil
        }
    }

    var scalesX: Bool {
        switch self {
        case .top, .bottom: false
        case .topLeft, .topRight, .bottomRight, .bottomLeft, .left, .right: true
        default: false
        }
    }

    var scalesY: Bool {
        switch self {
        case .left, .right: false
        case .topLeft, .topRight, .bottomRight, .bottomLeft, .top, .bottom: true
        default: false
        }
    }
}

struct AnnoSelectionBounds {
    var box: Box
    var transform: Mat

    var pageCorners: [Vec] { transform.applyToPoints(box.corners) }
    var pageCenter: Vec { transform.applyToPoint(box.center) }

    func pagePoint(_ normalized: Vec) -> Vec {
        transform.applyToPoint(Vec(box.x + box.w * normalized.x, box.y + box.h * normalized.y))
    }
}

enum AnnoInteraction {
    case idle
    case drawing(id: AnnoShapeID, origin: Vec)
    case creatingGeo(id: AnnoShapeID, origin: Vec)
    case creatingArrow(id: AnnoShapeID)
    case brushing(origin: Vec)
    case translating(origin: Vec, initial: [AnnoShapeID: Vec])
    case resizing(handle: AnnoSelectionHandle, bounds: AnnoSelectionBounds, initial: AnnoDocument.Snapshot)
    case rotating(center: Vec, startAngle: Double, initial: AnnoDocument.Snapshot)
    case draggingArrowHandle(id: AnnoShapeID, handle: AnnoSelectionHandle)
}

struct PointerInfo {
    var screenPoint: Vec
    var pagePoint: Vec
    var pressure: Double = 0.5
    var isPen = false
    var shift = false
    var alt = false
    var command = false
}

struct AnnoViewport {
    var imageFrame: CGRect = .zero
    var imageSize: CGSize = .zero

    var scale: Double {
        guard imageSize.width > 0, imageFrame.width > 0 else { return 1 }
        return Double(imageFrame.width / imageSize.width)
    }
}

@MainActor
final class AnnoEditor {
    private(set) var document = AnnoDocument()
    var selectedIds: Set<AnnoShapeID> = []
    var viewport = AnnoViewport()

    var tool: AnnotationTool = .rectangle {
        didSet {
            guard tool != oldValue else { return }
            stopEditingText()
            if tool != .select { selectedIds.removeAll() }
        }
    }

    var currentSwatch: AnnotationSwatch = .red
    var currentStrokeWidth: Double = 4
    var currentRedactionKind: RedactionKind = .blur
    var currentRedactionDensity: Double = 0.55
    var currentTextStyle: AnnotationTextStyle = .plain
    var currentTextFontSize: Double = 48
    var currentFontFamily: AnnoFontFamily = .pro
    var currentTextIsBold = true
    var currentTextIsItalic = false
    var currentTextIsUnderline = false
    var currentTextAlign: TextAlign = .start
    var currentArrowheadStart: Arrowhead = .none
    var currentArrowheadEnd: Arrowhead = .arrow

    var editingTextId: AnnoShapeID?
    var onEditingTextChanged: ((AnnoShapeID?) -> Void)?

    var pageLimits: Box?

    private(set) var interaction: AnnoInteraction = .idle
    private(set) var brush: Box?
    private(set) var hintedBindingId: AnnoShapeID?

    private var undoStack: [AnnoDocument.Snapshot] = []
    private var redoStack: [AnnoDocument.Snapshot] = []

    var onChange: (() -> Void)?

    func notifyChanged() { onChange?() }

    func setInteraction(_ interaction: AnnoInteraction) { self.interaction = interaction }
    func setBrush(_ brush: Box?) { self.brush = brush }
    func setHintedBinding(_ id: AnnoShapeID?) { hintedBindingId = id }


    func pageToScreen(_ p: Vec) -> Vec {
        let s = viewport.scale
        return Vec(
            Double(viewport.imageFrame.minX) + p.x * s,
            Double(viewport.imageFrame.minY) + p.y * s
        )
    }

    func screenToPage(_ p: Vec) -> Vec {
        let s = viewport.scale
        guard s != 0 else { return p }
        return Vec(
            (p.x - Double(viewport.imageFrame.minX)) / s,
            (p.y - Double(viewport.imageFrame.minY)) / s
        )
    }

    func pageDistance(forScreen distance: Double) -> Double {
        let s = viewport.scale
        return s == 0 ? distance : distance / s
    }


    func replaceDocument(shapes: [AnnoShape], bindings: [ArrowBinding] = []) {
        document.restore(AnnoDocument.Snapshot(shapes: shapes, bindings: bindings))
        selectedIds.removeAll()
        editingTextId = nil
        interaction = .idle
        undoStack.removeAll()
        redoStack.removeAll()
        notifyChanged()
    }

    var shapes: [AnnoShape] { document.shapes }


    func markUndo() {
        undoStack.append(document.snapshot())
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(document.snapshot())
        document.restore(snapshot)
        selectedIds = selectedIds.filter { document.shape($0) != nil }
        stopEditingText()
        notifyChanged()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(document.snapshot())
        document.restore(snapshot)
        selectedIds = selectedIds.filter { document.shape($0) != nil }
        stopEditingText()
        notifyChanged()
    }


    var selectedShapes: [AnnoShape] {
        document.shapes.filter { selectedIds.contains($0.id) }
    }

    var selectionBounds: AnnoSelectionBounds? {
        let selected = selectedShapes
        guard !selected.isEmpty else { return nil }
        if selected.count == 1 {
            let shape = selected[0]
            return AnnoSelectionBounds(box: document.geometry(shape).bounds, transform: shape.pageTransform)
        }
        let boxes = selected.compactMap { document.pageBounds($0.id) }
        guard !boxes.isEmpty else { return nil }
        return AnnoSelectionBounds(box: Box.common(boxes), transform: .identity)
    }

    func hitShape(at pagePoint: Vec) -> AnnoShape? {
        let margin = Swift.max(4, pageDistance(forScreen: 8))
        for shape in document.shapes.reversed() {
            let localPoint = document.pointInShapeSpace(shape, pagePoint)
            let geometry = document.geometry(shape)
            if geometry.hitTestPoint(localPoint, margin: margin, hitInside: shape.isFilled) {
                return shape
            }
        }
        return nil
    }

    func shapes(in box: Box) -> [AnnoShape] {
        let polygon = box.corners
        return document.shapes.filter { shape in
            let localPolygon = shape.pageTransform.inverse.applyToPoints(polygon)
            return document.geometry(shape).overlapsPolygon(localPolygon)
        }
    }

    func selectAll() {
        selectedIds = Set(document.shapes.map { $0.id })
        tool = .select
        notifyChanged()
    }

    func deleteSelected() {
        guard !selectedIds.isEmpty else { return }
        markUndo()
        document.delete(selectedIds)
        selectedIds.removeAll()
        stopEditingText()
        notifyChanged()
    }

    func nudgeSelected(dx: Double, dy: Double) {
        guard !selectedIds.isEmpty else { return }
        var dx = dx
        var dy = dy
        if let limits = pageLimits {
            let boxes = selectedIds.compactMap { document.pageBounds($0) }
            if !boxes.isEmpty {
                let box = Box.common(boxes)
                dx = Swift.max(limits.minX - box.minX, Swift.min(dx, limits.maxX - box.maxX))
                dy = Swift.max(limits.minY - box.minY, Swift.min(dy, limits.maxY - box.maxY))
            }
        }
        guard dx != 0 || dy != 0 else { return }
        markUndo()
        for id in selectedIds {
            document.update(id) { shape in
                shape.x += dx
                shape.y += dy
            }
        }
        notifyChanged()
    }

    func handle(at screenPoint: Vec) -> AnnoSelectionHandle? {
        guard let bounds = selectionBounds else { return nil }
        let hitRadius = 9.0

        if selectedIds.count == 1, let shape = selectedShapes.first, shape.isArrow,
           let info = document.arrowInfo(shape.id) {
            let transform = shape.pageTransform
            let candidates: [(AnnoSelectionHandle, Vec)] = [
                (.arrowStart, info.start.handle),
                (.arrowMiddle, info.middle),
                (.arrowEnd, info.end.handle),
            ]
            for (handle, localPoint) in candidates {
                let screen = pageToScreen(transform.applyToPoint(localPoint))
                if Vec.dist(screen, screenPoint) <= hitRadius { return handle }
            }
            return nil
        }

        let handles: [(AnnoSelectionHandle, Vec)] = [
            (.topLeft, Vec(0, 0)), (.top, Vec(0.5, 0)), (.topRight, Vec(1, 0)),
            (.right, Vec(1, 0.5)), (.bottomRight, Vec(1, 1)), (.bottom, Vec(0.5, 1)),
            (.bottomLeft, Vec(0, 1)), (.left, Vec(0, 0.5)),
        ]
        for (handle, normalized) in handles {
            let screen = pageToScreen(bounds.pagePoint(normalized))
            if Vec.dist(screen, screenPoint) <= hitRadius { return handle }
        }

        let corners = [Vec(0, 0), Vec(1, 0), Vec(1, 1), Vec(0, 1)]
        let center = pageToScreen(bounds.pageCenter)
        for (i, normalized) in corners.enumerated() {
            let screen = pageToScreen(bounds.pagePoint(normalized))
            let outward = Vec.sub(screen, center).uni
            let rotatePoint = Vec.add(screen, Vec.mul(outward, 14))
            if Vec.dist(rotatePoint, screenPoint) <= hitRadius { return .rotate(corner: i) }
        }
        return nil
    }


    func pageStrokeWidth(_ sliderValue: Double) -> Double {
        let edge = Swift.max(Double(viewport.imageSize.width), Double(viewport.imageSize.height))
        guard edge > 0 else { return sliderValue }
        return Swift.max(1, sliderValue * edge / 900)
    }

    func sliderStrokeWidth(_ pageWidth: Double) -> Double {
        let edge = Swift.max(Double(viewport.imageSize.width), Double(viewport.imageSize.height))
        guard edge > 0 else { return pageWidth }
        return pageWidth * 900 / edge
    }

    func applyStyleToSelection(_ apply: (inout AnnoShape) -> Void) {
        guard !selectedIds.isEmpty else { return }
        markUndo()
        for id in selectedIds {
            document.update(id) { apply(&$0) }
        }
        notifyChanged()
    }
}
