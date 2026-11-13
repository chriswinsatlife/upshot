import AppKit
import CoreGraphics

nonisolated enum AnnotationTextStyle: String, CaseIterable, Codable, Identifiable {
    case plain
    case label
    case callout

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AnnotationTextDecoration {
    static func padding(_ props: TextProps) -> Double {
        props.style == nil || props.style == .plain ? 0 : props.fontSize * 0.3
    }

    static func size(_ props: TextProps) -> CGSize {
        let text = TextMeasure.measure(props)
        let inset = padding(props)
        let tail = props.style == .callout ? props.fontSize * 0.45 : 0
        return CGSize(width: text.width + inset * 2, height: text.height + inset * 2 + tail)
    }

    static func elements(_ props: TextProps, includesText: Bool = true) -> [RenderElement] {
        let inset = padding(props)
        var elements: [RenderElement] = []
        if inset > 0 {
            let text = TextMeasure.measure(props)
            let rect = CGRect(x: 0, y: 0, width: text.width + inset * 2, height: text.height + inset * 2)
            let background = CGMutablePath()
            background.addRoundedRect(in: rect, cornerWidth: inset * 0.65, cornerHeight: inset * 0.65)
            if props.style == .callout {
                let tail = props.fontSize * 0.45
                background.move(to: CGPoint(x: inset, y: rect.maxY))
                background.addLine(to: CGPoint(x: inset, y: rect.maxY + tail))
                background.addLine(to: CGPoint(x: inset + tail, y: rect.maxY))
                background.closeSubpath()
            }
            elements.append(RenderElement(content: .path(background), fill: props.swatch.nsColor))
        }
        if includesText, !props.text.isEmpty {
            let glyphs = CGMutablePath()
            glyphs.addPath(TextMeasure.glyphPath(props), transform: CGAffineTransform(translationX: inset, y: inset))
            elements.append(RenderElement(
                content: .glyphs(glyphs),
                fill: inset > 0 ? props.swatch.numberedCircleTextNSColor : props.swatch.nsColor
            ))
        }
        return elements
    }
}
