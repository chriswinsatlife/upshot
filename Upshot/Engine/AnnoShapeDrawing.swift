import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum AnnoShapeDrawing {
    struct Target {
        var transform: CGAffineTransform
        var pageSize: CGSize
        var sample: ((CGRect) -> CGImage?)?
        var spotlightClip: CGPath?
        var isFlippedContext = false
        var redactionPreviewCache: AnnoRedactionPreviewCache? = nil

        var pageRect: CGRect { CGRect(origin: .zero, size: pageSize) }
    }

    nonisolated(unsafe) private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    nonisolated static func clearCaches() { ciContext.clearCaches() }

    static func draw(
        _ document: AnnoDocument,
        in context: CGContext,
        target: Target,
        skipping skipped: Set<AnnoShapeID> = []
    ) {
        let shapes = document.shapes.filter { !skipped.contains($0.id) }

        for shape in shapes where shape.isRedaction {
            drawRedaction(shape, document: document, in: context, target: target)
        }

        drawSpotlight(shapes.filter { $0.isHighlight }, in: context, target: target)

        for shape in shapes where !shape.isRedaction && !shape.isHighlight {
            drawShape(shape, document: document, in: context, target: target)
        }
    }


    static func drawShape(
        _ shape: AnnoShape,
        document: AnnoDocument,
        in context: CGContext,
        target: Target,
        textBackgroundOnly: Bool = false
    ) {
        let elements = if textBackgroundOnly, let props = shape.textProps {
            AnnotationTextDecoration.elements(props, includesText: false)
        } else {
            document.renderElements(shape.id)
        }
        guard !elements.isEmpty else { return }

        context.saveGState()
        context.concatenate(shape.pageTransform.cgAffineTransform.concatenating(target.transform))
        if shape.opacity < 1 { context.setAlpha(shape.opacity) }

        if shape.castsShadow == true {
            let scale = hypot(target.transform.a, target.transform.b)
            context.setShadow(
                offset: CGSize(width: 0, height: 3 * scale),
                blur: 6 * scale,
                color: NSColor.black.withAlphaComponent(0.35).cgColor
            )
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        for element in elements {
            switch element.content {
            case let .path(path), let .glyphs(path):
                if let fill = element.fill {
                    context.addPath(path)
                    context.setFillColor(fill.cgColor)
                    context.fillPath(using: element.usesEvenOddFill ? .evenOdd : .winding)
                }
                if let stroke = element.stroke {
                    context.addPath(path)
                    context.setStrokeColor(stroke.cgColor)
                    context.setLineWidth(element.strokeWidth)
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    if element.dashes.isEmpty {
                        context.setLineDash(phase: 0, lengths: [])
                    } else {
                        context.setLineDash(phase: element.dashPhase, lengths: element.dashes)
                    }
                    context.strokePath()
                    context.setLineDash(phase: 0, lengths: [])
                }
            case let .numbered(props):
                drawNumbered(props, in: context)
            case .redaction, .spotlight:
                break
            }
        }
        if shape.castsShadow == true { context.endTransparencyLayer() }
        context.restoreGState()
    }


    private static func drawNumbered(_ props: NumberedProps, in context: CGContext) {
        let rect = CGRect(x: 0, y: 0, width: props.diameter, height: props.diameter)
        let outlineWidth = Swift.max(1, props.diameter * 0.055)

        context.setFillColor(props.swatch.nsColor.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(props.swatch.numberedCircleOutlineNSColor.cgColor)
        context.setLineWidth(outlineWidth)
        context.strokeEllipse(in: rect.insetBy(dx: outlineWidth / 2, dy: outlineWidth / 2))

        let text = String(props.value)
        var textProps = TextProps()
        textProps.text = text
        textProps.swatch = props.swatch
        textProps.fontSize = props.diameter * numberedFontScale(digits: text.count)
        textProps.fontFamily = .pro
        textProps.isBold = true
        textProps.align = .start

        let path = TextMeasure.glyphPath(textProps)
        let glyphBounds = path.boundingBoxOfPath
        var transform = CGAffineTransform(
            translationX: props.diameter / 2 - glyphBounds.midX,
            y: props.diameter / 2 - glyphBounds.midY
        )
        guard let positioned = path.copy(using: &transform) else { return }
        context.addPath(positioned)
        context.setFillColor(props.swatch.numberedCircleTextNSColor.cgColor)
        context.fillPath(using: .winding)
    }

    private static func numberedFontScale(digits: Int) -> Double {
        if digits <= 2 { return 0.54 }
        if digits == 3 { return 0.44 }
        return 0.34
    }


    private static func drawSpotlight(_ shapes: [AnnoShape], in context: CGContext, target: Target) {
        guard !shapes.isEmpty else { return }

        context.saveGState()
        if let clip = target.spotlightClip {
            context.addPath(clip)
            context.clip()
        } else {
            context.clip(to: target.pageRect.applying(target.transform))
        }

        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setBlendMode(.normal)
        context.setFillColor(
            NSColor.black.withAlphaComponent(AnnotationHighlightMetrics.overlayOpacity).cgColor
        )
        context.fill(target.pageRect.applying(target.transform))

        context.saveGState()
        context.setBlendMode(.clear)
        for shape in shapes {
            guard case let .highlight(props) = shape.kind else { continue }
            var transform = shape.pageTransform.cgAffineTransform.concatenating(target.transform)
            context.addPath(CGPath(
                rect: CGRect(x: 0, y: 0, width: props.w, height: props.h),
                transform: &transform
            ))
            context.fillPath()
        }
        context.restoreGState()

        context.endTransparencyLayer()
        context.restoreGState()
    }


    private static func drawRedaction(
        _ shape: AnnoShape,
        document: AnnoDocument,
        in context: CGContext,
        target: Target
    ) {
        guard case let .redaction(props) = shape.kind, let sample = target.sample else { return }

        let localRect = CGRect(x: 0, y: 0, width: props.w, height: props.h)
        let full = shape.pageTransform.cgAffineTransform.concatenating(target.transform)
        let contextBounds = localRect.applying(full).integral
        guard contextBounds.width >= 1, contextBounds.height >= 1 else { return }

        let render = {
            guard let sampled = sample(contextBounds) else { return nil as CGImage? }
            return autoreleasepool {
                let targetScale = hypot(target.transform.a, target.transform.b)
                let sampleScale = Double(sampled.width) / max(1, contextBounds.width / max(targetScale, 0.0001))
                return AnnotationRedactionFilters.render(sampled, kind: props.kind, density: props.density, scale: sampleScale)
            }
        }
        let processed: CGImage?
        if let cache = target.redactionPreviewCache {
            processed = cache.image(kind: props.kind.rawValue, density: props.density, bounds: contextBounds, render: render)
        } else {
            processed = render()
        }
        guard let processed else { return }

        context.saveGState()
        context.concatenate(full)
        context.clip(to: localRect)
        context.concatenate(full.inverted())
        context.interpolationQuality = props.kind == .pixelate ? .none : .high
        if target.isFlippedContext {
            context.translateBy(x: 0, y: contextBounds.midY)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -contextBounds.midY)
        }
        context.draw(processed, in: contextBounds)
        context.restoreGState()
    }

}
