import AppKit
import CoreText

struct OverlayTextLayout {
    static let magnifierFont = font(size: 11, weight: .medium, monospaced: true)
    static let instructionFont = font(size: 13, weight: .medium)
    static let selectionSizeFont = font(size: 12, weight: .semibold, monospacedDigits: true)
    static let selectionAspectFont = font(size: 12, weight: .medium, monospacedDigits: true)
    static let timelineTitleFont = font(size: 10, weight: .medium)
    static let timelineBadgeFont = font(size: 10, weight: .semibold)

    let line: CTLine
    let size: CGSize
    private let ascent: CGFloat
    private let descent: CGFloat

    init(_ text: String, font: CTFont, color: CGColor = CGColor(gray: 1, alpha: 1), maximumWidth: CGFloat? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let original = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        if let maximumWidth, CTLineGetTypographicBounds(original, nil, nil, nil) > maximumWidth {
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(original, Double(maximumWidth), .end, token) ?? token
        } else {
            line = original
        }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        self.ascent = ascent
        self.descent = descent
        size = CGSize(width: ceil(width), height: ceil(ascent + descent + leading))
    }

    func draw(at origin: CGPoint, in context: CGContext, flipped: Bool = false) {
        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        if flipped {
            context.translateBy(x: origin.x, y: origin.y + ascent)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
        } else {
            context.textPosition = CGPoint(x: origin.x, y: origin.y + ceil(descent))
        }
        CTLineDraw(line, context)
    }

    private static func font(size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false, monospacedDigits: Bool = false) -> CTFont {
        let font: NSFont
        if monospaced {
            font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        } else if monospacedDigits {
            font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        } else {
            font = NSFont.systemFont(ofSize: size, weight: weight)
        }
        return CTFontCreateCopyWithAttributes(font as CTFont, size, nil, nil)
    }
}
