import CoreGraphics
import Foundation
import SwiftUI

nonisolated struct RecordingStudioPadding: Codable, Equatable, Sendable {
    var top: CGFloat
    var bottom: CGFloat
    var left: CGFloat
    var right: CGFloat
    var linked: Bool

    init(top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, linked: Bool = true) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.linked = linked
    }

    init(uniform: CGFloat) {
        self.init(top: uniform, bottom: uniform, left: uniform, right: uniform)
    }

    var normalized: Self {
        func clamp(_ value: CGFloat, to maximum: CGFloat) -> CGFloat {
            value.isFinite ? min(max(value, 0), maximum) : 0
        }
        if linked { return Self(uniform: clamp(top, to: 100)) }
        return Self(top: clamp(top, to: 250), bottom: clamp(bottom, to: 250),
                    left: clamp(left, to: 100), right: clamp(right, to: 100), linked: false)
    }

    var topFraction: CGFloat { min(top, 100) * 0.002 }
    var bottomFraction: CGFloat { min(bottom, 100) * 0.002 }
    var leftFraction: CGFloat { left * 0.002 }
    var rightFraction: CGFloat { right * 0.002 }
    var isZero: Bool { top == 0 && bottom == 0 && left == 0 && right == 0 }

    mutating func setLinked(_ linked: Bool) {
        if linked {
            self = Self(uniform: min(100, ((top + bottom + left + right) / 4).rounded()))
        } else {
            self.linked = false
        }
    }
}

nonisolated struct RecordingStudioShadowLayer: Sendable {
    let offset: CGFloat
    let blur: CGFloat
    let alpha: CGFloat
}

extension RecordingStudioStyle {
    nonisolated var resolvedPaddingSides: RecordingStudioPadding {
        paddingSides?.normalized ?? RecordingStudioPadding(uniform: padding / 0.002)
    }

    nonisolated func shadowLayers(canvasSize: CGSize, opacity: CGFloat = 1) -> [RecordingStudioShadowLayer] {
        guard background != .none, shadow.isFinite, shadow > 0 else { return [] }
        if !usesLayeredShadow {
            guard shadow > 0.01 else { return [] }
            let blur = min(canvasSize.width, canvasSize.height) * 0.045 * shadow
            return [RecordingStudioShadowLayer(offset: blur * 0.35, blur: blur, alpha: 0.55 * shadow * opacity)]
        }
        let strength = min(max(shadow, 0), 1) * 2
        let scale = max(1, canvasSize.width) / 640 * strength
        return [
            RecordingStudioShadowLayer(offset: 12 * scale, blur: 28 * scale, alpha: 0.24 * strength * opacity),
            RecordingStudioShadowLayer(offset: 2 * scale, blur: 3 * scale, alpha: 0.38 * strength * opacity)
        ]
    }
}

struct RecordingStudioFrameShadowModifier: ViewModifier {
    let style: RecordingStudioStyle
    let canvasSize: CGSize
    var previewBackground: AnnotationBackgroundStyle?
    var isStylePreview = false

    private var resolvedStyle: RecordingStudioStyle {
        var resolved = style
        if let previewBackground { resolved.background = previewBackground }
        return resolved
    }

    func body(content: Content) -> some View {
        let layers = resolvedStyle.shadowLayers(canvasSize: canvasSize)
        let ambient = layers.first
        let contact = layers.dropFirst().first
        if style.usesLayeredShadow {
            content
                .shadow(color: .black.opacity(Double(ambient?.alpha ?? 0)), radius: ambient?.blur ?? 0, y: ambient?.offset ?? 0)
                .shadow(color: .black.opacity(Double(contact?.alpha ?? 0)), radius: contact?.blur ?? 0, y: contact?.offset ?? 0)
        } else {
            let short = min(canvasSize.width, canvasSize.height)
            let hidden = (previewBackground ?? style.background) == .none
            content.shadow(
                color: .black.opacity(hidden ? 0 : (isStylePreview ? 0.5 : 0.55) * style.shadow),
                radius: short * (isStylePreview ? 0.05 : 0.045) * style.shadow,
                y: short * (isStylePreview ? 0.02 : 0.016) * style.shadow
            )
        }
    }
}
