import AppKit
import CoreGraphics
import Foundation

struct RenderElement {
    enum Content {
        case path(CGPath)
        case redaction(RedactionProps)
        case spotlight(CGSize)
        case numbered(NumberedProps)
        case glyphs(CGPath)
    }

    var content: Content
    var fill: NSColor?
    var stroke: NSColor?
    var strokeWidth: Double = 1
    var usesEvenOddFill = false
    var dashes: [CGFloat] = []
    var dashPhase: CGFloat = 0

    var cgPath: CGPath? {
        switch content {
        case let .path(path), let .glyphs(path): path
        case .redaction, .spotlight, .numbered: nil
        }
    }

    var isRedaction: Bool {
        if case .redaction = content { return true }
        return false
    }

    var isSpotlight: Bool {
        if case .spotlight = content { return true }
        return false
    }
}

enum AnnoShapeRenderer {
    static func elements(for shape: AnnoShape, in document: AnnoDocument) -> [RenderElement] {
        switch shape.kind {
        case let .geo(props):
            geoElements(props)
        case let .draw(props):
            drawElements(props)
        case .arrow:
            arrowElements(shape, in: document)
        case let .text(props):
            textElements(props)
        case let .redaction(props):
            [RenderElement(content: .redaction(props))]
        case let .highlight(props):
            [RenderElement(content: .spotlight(CGSize(width: props.w, height: props.h)))]
        case let .numbered(props):
            [RenderElement(content: .numbered(props))]
        }
    }


    private static func textElements(_ props: TextProps) -> [RenderElement] {
        AnnotationTextDecoration.elements(props)
    }


    private static func drawElements(_ props: DrawProps) -> [RenderElement] {
        guard !props.points.isEmpty else { return [] }

        let options = FreehandSettings.forDrawShape(
            isPen: props.isPen,
            isComplete: props.isComplete,
            strokeWidth: props.strokeWidth,
            forceComplete: false,
            forceSolid: false,
            smoothing: props.smoothing
        )
        let ink = SvgInk.render(props.points, options)
        return [RenderElement(
            content: .path(ink.path),
            fill: props.swatch.nsColor,
            stroke: nil,
            usesEvenOddFill: false
        )]
    }


    private static func geoElements(_ props: GeoProps) -> [RenderElement] {
        let path = GeoPaths.path(for: props)

        if props.fill != .none {
            return [RenderElement(
                content: .path(path.solidPath()),
                fill: props.swatch.nsColor,
                stroke: nil
            )]
        }
        return [strokeElement(
            path: path,
            dash: props.dash,
            strokeWidth: props.strokeWidth,
            color: props.swatch.nsColor,
            seed: ""
        )]
    }

    private static func strokeElement(
        path: PathBuilder,
        dash: DashStyle,
        strokeWidth: Double,
        color: NSColor,
        seed: String
    ) -> RenderElement {
        switch dash {
        case .draw:
            let opts = PathBuilder.DrawOptions(strokeWidth: strokeWidth, randomSeed: seed)
            return RenderElement(
                content: .path(path.drawPath(opts)),
                fill: nil,
                stroke: color,
                strokeWidth: strokeWidth
            )
        case .solid:
            return RenderElement(
                content: .path(path.solidPath()),
                fill: nil,
                stroke: color,
                strokeWidth: strokeWidth
            )
        case .dashed, .dotted:
            let segments = path.dashedSegments(strokeWidth: strokeWidth, style: dash)
            let combined = CGMutablePath()
            for segment in segments { combined.addPath(segment.path) }
            let first = segments.first
            return RenderElement(
                content: .path(combined),
                fill: nil,
                stroke: color,
                strokeWidth: strokeWidth,
                dashes: first?.dashes ?? [],
                dashPhase: first?.phase ?? 0
            )
        }
    }


    private static func arrowElements(_ shape: AnnoShape, in document: AnnoDocument) -> [RenderElement] {
        guard let props = shape.arrowProps,
              let info = document.arrowInfo(shape.id),
              info.isValid else { return [] }

        if props.isMeasurement == true { return AnnotationMeasurement.elements(props) }
        var elements: [RenderElement] = []
        elements.append(strokeElement(
            path: ArrowPath.body(info),
            dash: props.dash,
            strokeWidth: props.strokeWidth,
            color: props.swatch.nsColor,
            seed: shape.id.raw
        ))

        for side in [ArrowTerminal.start, ArrowTerminal.end] {
            guard let head = Arrowheads.path(info, side, props.strokeWidth) else { continue }
            elements.append(RenderElement(
                content: .path(head.path.solidPath()),
                fill: head.isFilled ? props.swatch.nsColor : nil,
                stroke: props.swatch.nsColor,
                strokeWidth: props.strokeWidth
            ))
        }

        return elements
    }
}
