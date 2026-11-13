import AppKit
import CoreGraphics
import CoreText
import Foundation

enum AnnoFontFamily: String, CaseIterable, Codable, Identifiable {
    case pro
    case compact
    case rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pro: "SF Pro"
        case .compact: "SF Compact"
        case .rounded: "SF Rounded"
        }
    }
}

enum TextMeasure {
    private static let lock = NSLock()
    private static let fontLock = NSLock()
    private static var fonts: [FontKey: NSFont] = [:]

    private struct FontKey: Hashable {
        let family: String
        let size: CGFloat
        let opticalSize: Double
        let bold: Bool
        let italic: Bool
    }

    private static let unbounded: CGFloat = 1_000_000

    static let minWidth: Double = 16

    static let lineHeightMultiple: Double = 1.35

    static func font(_ props: TextProps, opticalSize: Double? = nil) -> NSFont {
        let size = Swift.max(1, CGFloat(props.fontSize))
        let opticalSize = Swift.max(1, opticalSize ?? props.fontSize)
        let key = FontKey(family: props.fontFamily.rawValue, size: size, opticalSize: opticalSize, bold: props.isBold, italic: props.isItalic)
        fontLock.lock()
        defer { fontLock.unlock() }
        if let font = fonts[key] { return font }
        let weight: NSFont.Weight = props.isBold ? .bold : .regular
        let base = NSFont.systemFont(ofSize: size, weight: weight)

        var descriptor = base.fontDescriptor
        switch props.fontFamily {
        case .pro:
            break
        case .rounded:
            if let rounded = descriptor.withDesign(.rounded) { descriptor = rounded }
        case .compact:
            if let compact = NSFont(name: "SFCompactText-Regular", size: size)
                ?? NSFont(name: "SF Compact Text", size: size) {
                descriptor = compact.fontDescriptor
            }
        }
        if props.isItalic {
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic))
        }
        descriptor = descriptor.addingAttributes([
            kCTFontOpticalSizeAttribute as NSFontDescriptor.AttributeName:
                opticalSize,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        if fonts.count > 512 { fonts.removeAll(keepingCapacity: true) }
        fonts[key] = font
        return font
    }

    static func lineHeight(_ props: TextProps) -> CGFloat {
        CGFloat(Swift.max(1, props.fontSize) * lineHeightMultiple)
    }

    static func paragraphStyle(_ props: TextProps) -> NSParagraphStyle {
        let height = lineHeight(props)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = props.align.nsTextAlignment
        paragraph.minimumLineHeight = height
        paragraph.maximumLineHeight = height
        paragraph.lineBreakMode = props.autoSize ? .byClipping : .byWordWrapping
        return paragraph
    }

    static func attributes(_ props: TextProps, color: NSColor? = nil) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(props),
            .foregroundColor: color ?? props.swatch.nsColor,
            .paragraphStyle: paragraphStyle(props),
        ]
        if props.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    static func attributedString(_ props: TextProps, color: NSColor? = nil) -> NSAttributedString {
        NSAttributedString(string: props.text, attributes: attributes(props, color: color))
    }


    private static func layout(
        _ props: TextProps,
        containerWidth: CGFloat
    ) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(attributedString: attributedString(props, color: .black))
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: containerWidth, height: unbounded))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        _ = layoutManager.glyphRange(for: container)
        return (storage, layoutManager, container)
    }

    private static func lockedContainerWidth(_ props: TextProps) -> CGFloat {
        guard props.autoSize else { return CGFloat(Swift.max(minWidth, floor(props.w))) }
        if let cached = widthCache[props] { return cached }

        var probe = props
        probe.align = .start
        let (storage, layoutManager, container) = layout(probe, containerWidth: unbounded)
        let width = withExtendedLifetime(storage) {
            Swift.max(CGFloat(minWidth), ceil(layoutManager.usedRect(for: container).width) + 1)
        }

        if widthCache.count > 512 { widthCache.removeAll(keepingCapacity: true) }
        widthCache[props] = width
        return width
    }


    private static var widthCache: [TextProps: CGFloat] = [:]
    private static var sizeCache: [TextProps: CGSize] = [:]
    private static var pathCache: [TextProps: CGPath] = [:]

    static func measure(_ props: TextProps) -> CGSize {
        lock.lock()
        defer { lock.unlock() }
        if let cached = sizeCache[props] { return cached }

        let size = computeSize(props)
        if sizeCache.count > 512 { sizeCache.removeAll(keepingCapacity: true) }
        sizeCache[props] = size
        return size
    }

    private static func computeSize(_ props: TextProps) -> CGSize {
        let height = lineHeight(props)
        let width = lockedContainerWidth(props)

        guard !props.text.isEmpty else {
            return CGSize(width: width, height: height)
        }

        let (storage, layoutManager, container) = layout(props, containerWidth: width)
        return withExtendedLifetime(storage) {
            let used = layoutManager.usedRect(for: container)
            return CGSize(width: width, height: Swift.max(height, ceil(used.height)))
        }
    }


    static func glyphPath(_ props: TextProps) -> CGPath {
        lock.lock()
        defer { lock.unlock() }
        if let cached = pathCache[props] { return cached }

        let path = buildGlyphPath(props)
        if pathCache.count > 256 { pathCache.removeAll(keepingCapacity: true) }
        pathCache[props] = path
        return path
    }

    private static func buildGlyphPath(_ props: TextProps) -> CGPath {
        guard !props.text.isEmpty else { return CGMutablePath() }

        let (storage, layoutManager, container) = layout(props, containerWidth: lockedContainerWidth(props))
        let result = CGMutablePath()
        let glyphRange = layoutManager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return result }
        defer { withExtendedLifetime(storage) {} }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineRange, _ in
            var lineFont: NSFont?
            var baseline: CGFloat?

            for glyphIndex in lineRange.location..<(lineRange.location + lineRange.length) {
                let property = layoutManager.propertyForGlyph(at: glyphIndex)
                guard !property.contains(.null), !property.contains(.controlCharacter) else { continue }

                let glyph = layoutManager.cgGlyph(at: glyphIndex)
                guard glyph != 0 else { continue }

                let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
                guard charIndex < storage.length,
                      let font = storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont
                else { continue }

                let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let location = layoutManager.location(forGlyphAt: glyphIndex)
                lineFont = font
                baseline = fragment.origin.y + location.y

                guard let outline = CTFontCreatePathForGlyph(font as CTFont, glyph, nil) else { continue }

                let transform = CGAffineTransform(
                    a: 1, b: 0, c: 0, d: -1,
                    tx: fragment.origin.x + location.x,
                    ty: fragment.origin.y + location.y
                )
                result.addPath(outline, transform: transform)
            }

            if props.isUnderline, let lineFont, let baseline, usedRect.width > 0 {
                let thickness = Swift.max(1, lineFont.underlineThickness)
                result.addRect(CGRect(
                    x: usedRect.minX,
                    y: baseline - lineFont.underlinePosition - thickness / 2,
                    width: usedRect.width,
                    height: thickness
                ))
            }
        }
        return result
    }
}
