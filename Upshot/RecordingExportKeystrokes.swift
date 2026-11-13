import AppKit
import CoreGraphics
import CoreText
import Foundation
import SwiftUI

nonisolated enum RecordingKeystrokeSize: String, Codable, CaseIterable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var scale: CGFloat {
        switch self {
        case .small: 0.75
        case .medium: 1
        case .large: 1.4
        }
    }
}

nonisolated enum RecordingKeystrokeStyle: String, Codable, CaseIterable, Sendable {
    case dark = "Dark"
    case light = "Light"
}

nonisolated enum RecordingKeystrokeFilter: String, Codable, CaseIterable, Sendable {
    case commandsOnly = "Command Keys Only"
    case allKeys = "All Keys"

    func includes(_ event: RecordingKeystrokeEvent) -> Bool {
        if self == .allKeys { return true }
        return event.modifiers.contains { ["⌘", "⌃", "⌥", "fn"].contains($0) }
            || ["⏎", "⇥", "space", "⌫", "esc", "clear", "⌅", "↖", "⇞", "⌦", "↘", "⇟", "←", "→", "↓", "↑", "⇪"].contains(event.key)
            || (1...19).contains { event.key == "F\($0)" }
    }
}

nonisolated enum RecordingKeystrokePosition: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var column: Int {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft: 0
        case .topCenter, .middleCenter, .bottomCenter: 1
        case .topRight, .middleRight, .bottomRight: 2
        }
    }

    var row: Int {
        switch self {
        case .topLeft, .topCenter, .topRight: 0
        case .middleLeft, .middleCenter, .middleRight: 1
        case .bottomLeft, .bottomCenter, .bottomRight: 2
        }
    }

    var columnTitle: String { ["Left", "Center", "Right"][column] }
    var title: String { ["Top", "Middle", "Bottom"][row] + " " + columnTitle }

    func origin(pillSize: CGSize, card: CGRect, margin: CGFloat) -> CGPoint {
        let x = [card.minX + margin, card.midX - pillSize.width / 2, card.maxX - margin - pillSize.width][column]
        let y = [card.minY + margin, card.midY - pillSize.height / 2, card.maxY - margin - pillSize.height][row]
        return CGPoint(x: max(card.minX, min(x, card.maxX - pillSize.width)), y: max(card.minY, min(y, card.maxY - pillSize.height)))
    }
}

nonisolated struct RecordingKeystrokeAppearance: Codable, Equatable, Sendable {
    var size: RecordingKeystrokeSize = .medium
    var style: RecordingKeystrokeStyle = .dark
    var position: RecordingKeystrokePosition?
    var filter: RecordingKeystrokeFilter = .commandsOnly

    func resolvedPosition(fallback: RecordingKeystrokePlacement) -> RecordingKeystrokePosition {
        position ?? RecordingKeystrokePosition(rawValue: fallback.rawValue) ?? .bottomCenter
    }
}

nonisolated enum RecordingKeystrokeCaptionRenderer {
    static func draw(
        _ caption: KeystrokeCaptionFrame,
        appearance: RecordingKeystrokeAppearance,
        fallbackPlacement: RecordingKeystrokePlacement,
        card: CGRect,
        canvasHeight: CGFloat,
        opacity: Double = 1,
        in context: CGContext
    ) {
        let metrics = KeystrokeCaptionMetrics(cardHeight: card.height)
        let maximumWidth = max(1, card.width - metrics.margin * 2)
        let size = metrics.fontSize * appearance.size.scale
        let descriptor = NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor
        let rounded = descriptor.withDesign(.rounded) ?? descriptor
        let font = CTFontCreateWithFontDescriptor(rounded as CTFontDescriptor, size, nil)
        let components = KeystrokeCaptionMetrics.text(for: caption)
        let foreground: CGFloat = appearance.style == .dark ? 1 : 0
        let text = NSMutableAttributedString(string: components.modifiers, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: foreground, alpha: 0.7)
        ])
        text.append(NSAttributedString(string: components.key, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: foreground, alpha: 1)
        ]))
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let paddingHorizontal = metrics.paddingHorizontal * appearance.size.scale
        let paddingVertical = metrics.paddingVertical * appearance.size.scale
        let naturalSize = CGSize(width: width + paddingHorizontal * 2, height: ascent + descent + paddingVertical * 2)
        let fit = min(1, maximumWidth / max(1, naturalSize.width), max(1, card.height - metrics.margin * 2) / max(1, naturalSize.height))
        let pillSize = CGSize(width: naturalSize.width * fit, height: naturalSize.height * fit)
        let position = appearance.resolvedPosition(fallback: fallbackPlacement)
        let origin = position.origin(pillSize: pillSize, card: card, margin: metrics.margin)
        let pill = CGRect(x: origin.x, y: canvasHeight - origin.y - pillSize.height, width: pillSize.width, height: pillSize.height)
        context.saveGState()
        context.setAlpha(caption.opacity * opacity)
        context.translateBy(x: pill.midX, y: pill.midY)
        context.scaleBy(x: caption.scale, y: caption.scale)
        context.translateBy(x: -pill.width / 2, y: -pill.height / 2)
        context.scaleBy(x: fit, y: fit)
        let radius = metrics.cornerRadius * appearance.size.scale
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: naturalSize), cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(gray: appearance.style == .dark ? 0 : 1, alpha: appearance.style == .dark ? 0.62 : 0.9))
        context.fillPath()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: paddingHorizontal, y: naturalSize.height / 2 - (ascent - descent) / 2)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

struct RecordingStyledKeystrokeCaptionView: View {
    let caption: KeystrokeCaptionFrame
    let appearance: RecordingKeystrokeAppearance
    let fallbackPlacement: RecordingKeystrokePlacement
    let cardSize: CGSize

    var body: some View {
        Canvas { context, size in
            context.withCGContext { graphics in
                graphics.translateBy(x: 0, y: size.height)
                graphics.scaleBy(x: 1, y: -1)
                RecordingKeystrokeCaptionRenderer.draw(caption, appearance: appearance, fallbackPlacement: fallbackPlacement, card: CGRect(origin: .zero, size: size), canvasHeight: size.height, in: graphics)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .allowsHitTesting(false)
    }
}
