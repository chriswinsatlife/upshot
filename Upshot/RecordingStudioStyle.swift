import CoreGraphics
import Foundation

nonisolated struct RecordingCameraBubbleSettings: Equatable {
    var isVisible = true

    var roundness: CGFloat = 0.25

    var layout = RecordingCameraLayout()

    var shrinksDuringZoom = true

    var zoomShrinkAmount: CGFloat = RecordingCameraBubbleSettings.defaultZoomShrinkAmount

    var beauty = StudioCameraBeauty()

    static let defaultZoomShrinkAmount: CGFloat = 0.1
    static let zoomShrinkAmountRange: ClosedRange<CGFloat> = 0.05...0.4
}

nonisolated struct RecordingStudioStyle: Equatable {
    static let defaultCursorScale: CGFloat = 1.7

    static var defaultBackground: AnnotationBackgroundStyle {
        guard let gradient = AnnotationBackgroundGradient.presets.last else { return .none }
        return .gradient(gradient)
    }

    var background: AnnotationBackgroundStyle = RecordingStudioStyle.defaultBackground

    var padding: CGFloat = 0.06

    var cornerRadius: CGFloat = 0.02

    var shadow: CGFloat = 0.45

    var cursorScale: CGFloat = RecordingStudioStyle.defaultCursorScale
    var hidesCursor = false
    var cursorStyle = RecordingCursorStyle.system

    var invertsCursor = false
    var camera = RecordingCameraBubbleSettings()
}

nonisolated struct RecordingStudioLayout: Sendable, Equatable {

    static func originalCanvasSize(
        sourceSize: CGSize,
        style: RecordingStudioStyle,
        contentCropRect: CGRect
    ) -> CGSize {
        let crop = RecordingVideoCropGeometry.isCropped(contentCropRect)
            ? RecordingVideoCropGeometry.normalized(contentCropRect)
            : RecordingVideoCropGeometry.unit
        let visibleSize = CGSize(
            width: sourceSize.width * crop.width,
            height: sourceSize.height * crop.height
        )
        let padding = min(max(style.padding, 0), 0.475)
        let inset = min(visibleSize.width, visibleSize.height) * padding / (1 - 2 * padding)
        return CGSize(width: visibleSize.width + 2 * inset, height: visibleSize.height + 2 * inset)
    }

    let canvasSize: CGSize
    let cardRect: CGRect
    let cardCornerRadius: CGFloat
    let bubbleRect: CGRect
    let bubbleCornerRadius: CGFloat

    let contentFillSize: CGSize

    var contentCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var screenOpacity: CGFloat = 1
    var cameraOpacity: CGFloat = 1

    var cameraCutout: CGFloat = 0

    enum ContentMode: Sendable {

        case fill

        case fit
    }

    static func bubbleMargin(forMinDimension minDimension: CGFloat) -> CGFloat {
        (minDimension * 0.03).rounded()
    }

    static func make(
        canvasSize: CGSize,
        style: RecordingStudioStyle,
        usesUniformPadding: Bool = false,
        contentAspect: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        contentCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> RecordingStudioLayout {
        let minDimension = min(canvasSize.width, canvasSize.height)
        let inset = usesUniformPadding
            ? min(max(style.padding, 0), 0.475) * minDimension
            : (style.padding * minDimension).rounded()

        let cardScale = max(0.05, 1 - 2 * inset / minDimension)
        var cardSize = usesUniformPadding ? CGSize(
            width: canvasSize.width - 2 * inset,
            height: canvasSize.height - 2 * inset
        ) : CGSize(
            width: (canvasSize.width * cardScale).rounded(),
            height: (canvasSize.height * cardScale).rounded()
        )
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalizedCrop = contentCropRect.standardized.intersection(unit)
        let crop = normalizedCrop.width > 0.0001 && normalizedCrop.height > 0.0001
            ? normalizedCrop
            : unit
        let hasContentCrop = crop.minX > 0.0005
            || crop.minY > 0.0005
            || crop.width < 0.999
            || crop.height < 0.999
        let sourceAspect = contentAspect ?? (canvasSize.height > 0 ? canvasSize.width / canvasSize.height : 1)
        let cardAspect: CGFloat? = if hasContentCrop {
            sourceAspect * crop.width / crop.height
        } else if case .fit = contentMode {
            contentAspect
        } else {
            nil
        }
        if let cardAspect, cardAspect > 0, !usesUniformPadding {

            let fitHeight = min(cardSize.height, cardSize.width / cardAspect)
            cardSize = CGSize(
                width: (cardAspect * fitHeight).rounded(),
                height: fitHeight.rounded()
            )
        }
        let cardRect = CGRect(
            x: usesUniformPadding ? (canvasSize.width - cardSize.width) / 2
                : ((canvasSize.width - cardSize.width) / 2).rounded(),
            y: usesUniformPadding ? (canvasSize.height - cardSize.height) / 2
                : ((canvasSize.height - cardSize.height) / 2).rounded(),
            width: cardSize.width,
            height: cardSize.height
        )
        let cardCornerRadius = style.cornerRadius * minDimension

        var contentFillSize = cardRect.size
        if hasContentCrop {

            let fillHeight = max(
                cardRect.height / crop.height,
                cardRect.width / (crop.width * sourceAspect)
            )
            contentFillSize = CGSize(width: sourceAspect * fillHeight, height: fillHeight)
        } else if let contentAspect, contentAspect > 0, cardRect.height > 0 {
            let fillHeight = max(cardRect.height, cardRect.width / contentAspect)
            contentFillSize = CGSize(
                width: contentAspect * fillHeight,
                height: fillHeight
            )
        }

        return RecordingStudioLayout(
            canvasSize: canvasSize,
            cardRect: cardRect,
            cardCornerRadius: cardCornerRadius,
            bubbleRect: .zero,
            bubbleCornerRadius: 0,
            contentFillSize: contentFillSize,
            contentCropRect: crop,
            cameraOpacity: 0
        )
    }

    func frameRect(for viewport: ViewportFrame) -> CGRect {
        let drawWidth = contentFillSize.width * viewport.magnification
        let drawHeight = contentFillSize.height * viewport.magnification
        return CGRect(
            x: cardRect.midX - viewport.anchor.x * drawWidth,
            y: cardRect.midY - viewport.anchor.y * drawHeight,
            width: drawWidth,
            height: drawHeight
        )
    }
}

nonisolated enum RecordingVideoCropGeometry {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func normalized(_ requested: CGRect) -> CGRect {
        let crop = requested.standardized.intersection(unit)
        guard crop.width > 0.0001, crop.height > 0.0001 else { return unit }
        return crop
    }

    static func isCropped(_ requested: CGRect) -> Bool {
        let crop = normalized(requested)
        return crop.minX > 0.0005
            || crop.minY > 0.0005
            || crop.width < 0.999
            || crop.height < 0.999
    }

    static func viewport(_ base: ViewportFrame, crop requested: CGRect) -> ViewportFrame {
        let crop = normalized(requested)
        guard isCropped(crop) else { return base }

        let magnification = max(base.magnification, 1)
        let center = CGPoint(x: crop.midX, y: crop.midY)
        let halfWidth = crop.width / CGFloat(2 * magnification)
        let halfHeight = crop.height / CGFloat(2 * magnification)
        let target = CGPoint(
            x: min(max(base.anchor.x, crop.minX + halfWidth), crop.maxX - halfWidth),
            y: min(max(base.anchor.y, crop.minY + halfHeight), crop.maxY - halfHeight)
        )

        let progress = CGFloat(min(max((magnification - 1) / 0.12, 0), 1))
        return ViewportFrame(
            magnification: magnification,
            anchor: CGPoint(
                x: center.x + (target.x - center.x) * progress,
                y: center.y + (target.y - center.y) * progress
            )
        )
    }
}
