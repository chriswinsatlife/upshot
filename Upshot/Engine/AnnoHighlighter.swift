import CoreGraphics
import Foundation

extension AnnoEditor {
    func matchingTextBoxes(in rect: CGRect) -> [CGRect] {
        let selection = rect.insetBy(dx: -pageDistance(forScreen: 3), dy: -pageDistance(forScreen: 3))
        return normalizedTextBoxes.map { bounds in
            CGRect(
                x: bounds.minX * viewport.imageSize.width,
                y: bounds.minY * viewport.imageSize.height,
                width: bounds.width * viewport.imageSize.width,
                height: bounds.height * viewport.imageSize.height
            ).insetBy(dx: -2, dy: -2)
        }.filter { $0.intersects(selection) }
    }

    func commitSnappedHighlighter(_ id: AnnoShapeID) {
        guard let shape = document.shape(id), let props = shape.geoProps else { return }
        let rect = highlighterDragRect ?? CGRect(x: shape.x, y: shape.y, width: props.w, height: props.h)
        let boxes = matchingTextBoxes(in: rect)
        var identifiers: Set<AnnoShapeID> = []
        for (index, box) in boxes.enumerated() {
            var highlighted = shape
            highlighted.id = index == 0 ? id : AnnoShapeID()
            highlighted.x = box.minX
            highlighted.y = box.minY
            var properties = props
            properties.w = box.width
            properties.h = box.height
            highlighted.kind = .geo(properties)
            if index == 0 { document.update(highlighted) } else { document.add(highlighted) }
            identifiers.insert(highlighted.id)
        }
        selectedIds = identifiers.isEmpty ? [id] : identifiers
        tool = .select
        highlighterDragRect = nil
        AppLog.event("annotation", "annotation_highlighter_committed", fields: ["boxes": String(describing: boxes.count), "snapped": String(describing: String(!boxes.isEmpty))])
    }
}
