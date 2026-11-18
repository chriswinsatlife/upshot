import CoreGraphics
import Foundation

nonisolated enum RecordingClickEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case impact
    case none
    case spotlight
    case ripple
    case echo
    case burst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .impact: "Impact"
        case .none: "None"
        case .spotlight: "Spotlight"
        case .ripple: "Ripple"
        case .echo: "Echo"
        case .burst: "Burst"
        }
    }
}

nonisolated struct RecordingClickEffectSettings: Sendable, Equatable {
    static let defaultColor = "#9CA3AF"
    static let palette = [
        "#9CA3AF", "#FFFFFF", "#2563EB", "#EF4444", "#F59E0B", "#22C55E",
        "#A855F7", "#EC4899", "#14B8A6", "#F97316"
    ]

    var effect: RecordingClickEffect = .impact
    var color = RecordingClickEffectSettings.defaultColor
    var scale = 1.0
    var opacity = 1.0
    var duration: TimeInterval = 0.6

    static func normalizedColor(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "#" else { return nil }
        let digits = trimmed.dropFirst()
        guard digits.count == 3 || digits.count == 6,
              digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if digits.count == 3 {
            return "#" + digits.map { "\($0)\($0)" }.joined().uppercased()
        }
        return trimmed.uppercased()
    }

    var normalized: Self {
        var result = self
        result.color = Self.normalizedColor(color) ?? Self.defaultColor
        result.scale = scale.isFinite ? min(max(scale, 0.5), 2) : 1
        result.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        result.duration = duration.isFinite ? min(max(duration, 0.12), 1.2) : 0.6
        return result
    }

    var rgb: (red: Double, green: Double, blue: Double) {
        if effect == .impact { return PointerPressEffectStyle.color }
        let hex = Self.normalizedColor(color) ?? Self.defaultColor
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x9CA3AF
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    func location(for press: PointerPressFrame, cursor: CGPoint) -> CGPoint {
        if effect == .impact || effect == .burst { return press.location }
        return press.isPressed ? cursor : (press.releaseLocation ?? press.location)
    }

    func geometry(
        press: PointerPressFrame,
        referenceHeight: CGFloat,
        cursorScale: CGFloat,
        cursorHeight: CGFloat? = nil
    ) -> RecordingClickEffectGeometry {
        let settings = normalized
        guard effect != .none else { return RecordingClickEffectGeometry(components: []) }
        if effect == .impact {
            guard press.elapsed <= PointerPressEffectStyle.duration else {
                return RecordingClickEffectGeometry(components: [])
            }
            let original = PointerPressEffectStyle.geometry(
                progress: press.progress,
                referenceHeight: referenceHeight,
                cursorScale: cursorScale
            )
            return RecordingClickEffectGeometry(components: [
                .circle(radius: original.impactRadius, opacity: original.impactOpacity),
                .ring(radius: original.rippleRadius, width: original.rippleLineWidth, opacity: original.rippleOpacity)
            ])
        }
        let progress: Double
        if effect == .ripple || effect == .burst {
            progress = max(0, 1 - press.elapsed / (settings.duration * 0.5))
        } else if press.isPressed {
            progress = 0.75
        } else if let releaseAge = press.releaseAge {
            progress = 0.75 * max(0, 1 - releaseAge / settings.duration)
        } else {
            let age = press.elapsed - press.bounceDuration * 0.5
            progress = age >= 0 ? max(0, 1 - age / settings.duration) : 0
        }
        guard progress > 0 else { return RecordingClickEffectGeometry(components: []) }
        let unit = referenceHeight / 1_080
        let cursorSize = cursorHeight ?? (referenceHeight * PointerArtworkMetrics.heightRatio * cursorScale)
        let scale = CGFloat(settings.scale)
        let alpha = progress * settings.opacity
        let reveal = CGFloat(1 - progress)
        let radius = max(12 * unit, cursorSize * 0.55 * scale)
        let stroke = max(2 * unit, cursorSize * 0.08)
        switch effect {
        case .none, .impact:
            return RecordingClickEffectGeometry(components: [])
        case .ripple:
            return RecordingClickEffectGeometry(components: [
                .circle(
                    radius: max(0.5 * unit, CGFloat(1 - pow(progress, 3)) * cursorSize * 1.95 * scale),
                    opacity: progress * 0.35 * settings.opacity
                )
            ])
        case .spotlight:
            let outer = radius + reveal * cursorSize * scale
            let inner = max(radius * 0.72, outer * 0.76)
            return RecordingClickEffectGeometry(components: [
                .ring(radius: outer, width: max(1.25 * unit, stroke * 0.68), opacity: alpha * 0.28),
                .ring(radius: inner, width: max(1.5 * unit, stroke * 0.75), opacity: alpha * 0.5)
            ])
        case .echo:
            let outer = radius + reveal * cursorSize * 1.22 * scale
            let inner = max(radius * 0.58, outer * 0.62)
            return RecordingClickEffectGeometry(components: [
                .ring(radius: outer, width: stroke, opacity: alpha * 0.72),
                .ring(radius: inner, width: max(1.4 * unit, stroke * 0.72), opacity: alpha * 0.42),
                .circle(radius: max(3 * unit, radius * 0.18), opacity: alpha * 0.14)
            ])
        case .burst:
            let burstRadius = max(12 * unit, cursorSize * scale)
            let start = max(6 * unit, burstRadius * 0.2)
            let head = 1 - pow(1 - Double(reveal), 3)
            let tailPhase = max(0, (Double(reveal) - 0.18) / 0.82)
            let tail = 1 - pow(1 - tailPhase, 3)
            let inner = start + burstRadius * 1.7 * CGFloat(tail)
            let outer = start + burstRadius * CGFloat(0.12 + 1.7 * head)
            let components = (0..<10).map { index in
                let angle = -Double.pi / 2 + Double(index) * Double.pi * 2 / 10
                let path = CGMutablePath()
                path.move(to: CGPoint(x: cos(angle) * inner, y: sin(angle) * inner))
                path.addLine(to: CGPoint(x: cos(angle) * outer, y: sin(angle) * outer))
                return RecordingClickEffectComponent(
                    path: path.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 1),
                    opacity: alpha
                )
            }
            return RecordingClickEffectGeometry(components: components)
        }
    }
}

nonisolated extension RecordingEditDocument {
    var clickEffectSettings: RecordingClickEffectSettings {
        RecordingClickEffectSettings(
            effect: clickEffect ?? .impact,
            color: clickEffectColor ?? RecordingClickEffectSettings.defaultColor,
            scale: clickEffectScale ?? 1,
            opacity: clickEffectOpacity ?? 1,
            duration: clickEffectDuration ?? 0.6
        ).normalized
    }
}

nonisolated struct RecordingClickEffectComponent {
    var path: CGPath
    var opacity: Double

    static func circle(radius: CGFloat, opacity: Double) -> Self {
        Self(path: CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil), opacity: opacity)
    }

    static func ring(radius: CGFloat, width: CGFloat, opacity: Double) -> Self {
        let circle = Self.circle(radius: radius, opacity: opacity)
        return Self(
            path: circle.path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1),
            opacity: opacity
        )
    }
}

nonisolated struct RecordingClickEffectGeometry {
    var components: [RecordingClickEffectComponent]

    var bounds: CGRect {
        components.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
    }

    func draw(in context: CGContext, at point: CGPoint, settings: RecordingClickEffectSettings) {
        let color = settings.rgb
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: 1, y: -1)
        for component in components where component.opacity > 0 {
            context.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: component.opacity))
            context.addPath(component.path)
            context.fillPath()
        }
        context.restoreGState()
    }
}
