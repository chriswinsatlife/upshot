import AppKit
import CoreGraphics
import SwiftUI

nonisolated struct AnnotationBackgroundSettings: Equatable {
    var style: AnnotationBackgroundStyle = .none
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.018
    var shadow: CGFloat = 0.36
    var shadowStyle: AnnotationShadowStyle = .soft
    var border = AnnotationScreenshotBorderSettings()
    var aspectRatio: AnnotationBackgroundAspectRatio = .auto
    var alignment: AnnotationBackgroundAlignment = .center
    var customWallpaper: AnnotationCustomWallpaper?
    var camera = AnnotationCameraSettings()
    var progressiveBlur = AnnotationProgressiveBlurSettings()
    var watermark = AnnotationWatermarkSettings()
    var colorAdjustments = AnnotationColorAdjustments()
    var canvasExpansion = AnnotationCanvasExpansion()

    var isEnabled: Bool {
        style != .none
    }

    var usesCanvasLayout: Bool {
        isEnabled
            || camera.hasEffect
            || (progressiveBlur.isActive && progressiveBlur.edgeMode == .bleed)
    }

    var requiresCanvasLayout: Bool {
        usesCanvasLayout || border.isVisible
    }

    var effectiveCanvasAlignment: AnnotationBackgroundAlignment {
        camera.hasEffect || !usesCanvasLayout ? .center : alignment
    }

    var hasRenderableContent: Bool {
        isEnabled
            || camera.hasEffect
            || progressiveBlur.isActive
            || border.isVisible
            || watermark.isVisible
            || !colorAdjustments.isDefault
            || !canvasExpansion.isEmpty
    }
}

nonisolated struct AnnotationScreenshotBorderSettings: Equatable {
    var isEnabled = false
    var color: AnnotationSwatch = .white
    var thickness: CGFloat = 0.012
    var opacity: CGFloat = 1

    var isVisible: Bool {
        isEnabled && thickness > 0.0001 && opacity > 0.0001
    }

    func pixelThickness(for imageSize: CGSize) -> CGFloat {
        guard isVisible, imageSize.width > 0, imageSize.height > 0 else { return 0 }
        return max(0, thickness) * min(imageSize.width, imageSize.height)
    }
}

nonisolated struct AnnotationCameraSettings: Equatable {
    var panX: CGFloat = 0
    var panY: CGFloat = 0
    var tiltXDegrees: CGFloat = 0
    var tiltYDegrees: CGFloat = 0
    var rotationXDegrees: CGFloat = 0
    var rotationYDegrees: CGFloat = 0
    var rollDegrees: CGFloat = 0
    var fieldOfViewDegrees: CGFloat = 24
    var zoom: CGFloat = 1
    var projectionVersion: Int = 2

    var isDefault: Bool {
        let defaultFieldOfView: CGFloat = projectionVersion < 2 ? 45 : 24
        return isApproximatelyZero(panX)
            && isApproximatelyZero(panY)
            && isApproximatelyZero(tiltXDegrees)
            && isApproximatelyZero(tiltYDegrees)
            && isApproximatelyZero(rotationXDegrees)
            && isApproximatelyZero(rotationYDegrees)
            && isApproximatelyZero(rollDegrees)
            && abs(fieldOfViewDegrees - defaultFieldOfView) <= 0.0001
            && abs(zoom - 1) <= 0.0001
    }

    var hasEffect: Bool {
        !isApproximatelyZero(panX)
            || !isApproximatelyZero(panY)
            || !isApproximatelyZero(tiltXDegrees)
            || !isApproximatelyZero(tiltYDegrees)
            || !isApproximatelyZero(rotationXDegrees)
            || !isApproximatelyZero(rotationYDegrees)
            || !isApproximatelyZero(rollDegrees)
            || abs(zoom - 1) > 0.0001
    }

    private func isApproximatelyZero(_ value: CGFloat) -> Bool {
        abs(value) <= 0.0001
    }

    mutating func upgradeProjectionIfNeeded() {
        guard projectionVersion < 2 else { return }
        projectionVersion = 2
        if abs(fieldOfViewDegrees - 45) <= 0.0001 {
            fieldOfViewDegrees = 24
        }
    }
}

nonisolated enum AnnotationProgressiveBlurMode: String, CaseIterable, Identifiable, Sendable {
    case radial
    case directional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radial: "Radial"
        case .directional: "Directional"
        }
    }
}

nonisolated enum AnnotationProgressiveBlurEdgeMode: String, CaseIterable, Identifiable, Sendable {
    case clipped
    case bleed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipped: "Screenshot"
        case .bleed: "Scene"
        }
    }
}

nonisolated struct AnnotationProgressiveBlurSettings: Equatable, Sendable {
    var isEnabled = false
    var edgeMode: AnnotationProgressiveBlurEdgeMode = .bleed
    var mode: AnnotationProgressiveBlurMode = .radial
    var strength: CGFloat = 18
    var falloff: CGFloat = 0.55
    var focusSize: CGFloat = 0.45
    var focusPosition = CGPoint(x: 0.5, y: 0.5)
    var directionDegrees: CGFloat = 0

    var isActive: Bool {
        isEnabled && strength > 0.01
    }
}

nonisolated struct AnnotationWatermarkSettings: Equatable {
    var isEnabled = false
    var text = ""
    var density: CGFloat = 4
    var fontSize: CGFloat = 72
    var rotationDegrees: CGFloat = 45
    var opacity: CGFloat = 0.18
    var color: AnnotationWatermarkColor = .mercury
    var imageData: Data?
    var position: AnnotationWatermarkPosition = .tiled
    var imageWidth: CGFloat = 0.2

    var isVisible: Bool {
        isEnabled
            && (imageData != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && opacity > 0
    }
}

nonisolated enum AnnotationWatermarkTypography {
    private static let compactFontNames = [
        "SFCompact-Semibold",
        "SFCompactDisplay-Semibold",
        "SFCompactText-Semibold"
    ]

    private static let compactFontName = compactFontNames.first {
        NSFont(name: $0, size: 12) != nil
    }

    static func font(size: CGFloat) -> Font {
        let clampedSize = max(1, size)
        guard let compactFontName else {
            return .system(size: clampedSize, weight: .semibold)
        }

        return .custom(compactFontName, size: clampedSize)
    }

    static func nsFont(size: CGFloat) -> NSFont {
        let clampedSize = max(1, size)
        guard let compactFontName,
              let font = NSFont(name: compactFontName, size: clampedSize) else {
            return NSFont.systemFont(ofSize: clampedSize, weight: .semibold)
        }

        return font
    }
}

nonisolated struct AnnotationWatermarkColor: Equatable, Hashable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    static let mercury = AnnotationWatermarkColor(red: 0.90, green: 0.90, blue: 0.90)
    static let white = AnnotationWatermarkColor(red: 0.96, green: 0.96, blue: 0.96)

    static func custom(from color: Color) -> AnnotationWatermarkColor {
        custom(from: NSColor(color))
    }

    static func custom(from nsColor: NSColor) -> AnnotationWatermarkColor {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        return AnnotationWatermarkColor(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }
}

nonisolated enum AnnotationBackgroundAspectRatio: String, CaseIterable, Identifiable {
    case auto
    case square
    case fourThree
    case threeTwo
    case sixteenNine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .square: "1:1"
        case .fourThree: "4:3"
        case .threeTwo: "3:2"
        case .sixteenNine: "16:9"
        }
    }

    var value: CGFloat? {
        switch self {
        case .auto: nil
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        }
    }
}

nonisolated enum AnnotationBackgroundAlignment: String, CaseIterable, Identifiable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading: "Top left"
        case .top: "Top"
        case .topTrailing: "Top right"
        case .leading: "Left"
        case .center: "Center"
        case .trailing: "Right"
        case .bottomLeading: "Bottom left"
        case .bottom: "Bottom"
        case .bottomTrailing: "Bottom right"
        }
    }

    var xFactor: CGFloat {
        switch self {
        case .topLeading, .leading, .bottomLeading:
            0
        case .top, .center, .bottom:
            0.5
        case .topTrailing, .trailing, .bottomTrailing:
            1
        }
    }

    var yFactor: CGFloat {
        switch self {
        case .topLeading, .top, .topTrailing:
            0
        case .leading, .center, .trailing:
            0.5
        case .bottomLeading, .bottom, .bottomTrailing:
            1
        }
    }

    var sticksToTop: Bool {
        switch self {
        case .topLeading, .top, .topTrailing: true
        default: false
        }
    }

    var sticksToBottom: Bool {
        switch self {
        case .bottomLeading, .bottom, .bottomTrailing: true
        default: false
        }
    }

    var sticksToLeading: Bool {
        switch self {
        case .topLeading, .leading, .bottomLeading: true
        default: false
        }
    }

    var sticksToTrailing: Bool {
        switch self {
        case .topTrailing, .trailing, .bottomTrailing: true
        default: false
        }
    }

    var cornerRadiusMultipliers: (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
        switch self {
        case .center:
            (1, 1, 1, 1)
        case .top:
            (0, 0, 1, 1)
        case .bottom:
            (1, 1, 0, 0)
        case .leading:
            (0, 1, 0, 1)
        case .trailing:
            (1, 0, 1, 0)
        case .topLeading:
            (0, 0, 0, 1)
        case .topTrailing:
            (0, 0, 1, 0)
        case .bottomLeading:
            (0, 1, 0, 0)
        case .bottomTrailing:
            (1, 0, 0, 0)
        }
    }
}
