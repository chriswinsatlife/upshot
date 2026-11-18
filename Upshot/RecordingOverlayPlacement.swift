import CoreGraphics
import Foundation

nonisolated enum RecordingOverlayCoordinateSpace: String, Codable, CaseIterable, Sendable {
    case canvas
    case recording
}

nonisolated extension RecordingImageOverlay {
    func rect(canvasSize: CGSize, placement: RecordingOverlayPlacement) -> CGRect {
        let reference = placement.referenceRect(for: coordinateSpace, canvasSize: canvasSize)
        return rect(canvasSize: reference.size).offsetBy(dx: reference.minX, dy: reference.minY)
    }
}

nonisolated extension RecordingTextOverlayRenderer {
    static func layout(
        _ overlay: RecordingTextOverlay,
        canvasSize: CGSize,
        placement: RecordingOverlayPlacement
    ) -> Layout {
        let reference = placement.referenceRect(for: overlay.coordinateSpace, canvasSize: canvasSize)
        let result = layout(overlay, canvasSize: reference.size)
        return Layout(rect: result.rect.offsetBy(dx: reference.minX, dy: reference.minY))
    }

    static func draw(
        _ overlay: RecordingTextOverlay,
        atSourceTime time: TimeInterval,
        canvasSize: CGSize,
        placement: RecordingOverlayPlacement,
        in context: CGContext
    ) {
        placement.draw(space: overlay.coordinateSpace, canvasSize: canvasSize, in: context) { size in
            draw(overlay, atSourceTime: time, canvasSize: size, in: context)
        }
    }
}

nonisolated extension RecordingImageOverlayRenderer {
    static func draw(
        _ overlay: RecordingImageOverlay,
        image: RecordingOverlayImage,
        atSourceTime time: TimeInterval,
        canvasSize: CGSize,
        placement: RecordingOverlayPlacement,
        in context: CGContext
    ) {
        placement.draw(space: overlay.coordinateSpace, canvasSize: canvasSize, in: context) { size in
            draw(overlay, image: image, atSourceTime: time, canvasSize: size, in: context)
        }
    }
}

nonisolated struct RecordingOverlayPlacement: Sendable {
    let pictureRect: CGRect
    let clippingRect: CGRect
    let cornerRadius: CGFloat
    let opacity: CGFloat

    init(layout: RecordingStudioLayout, viewport: ViewportFrame) {
        pictureRect = layout.frameRect(for: viewport)
        clippingRect = layout.cardRect
        cornerRadius = layout.cardCornerRadius
        opacity = layout.screenOpacity
    }

    func referenceRect(for space: RecordingOverlayCoordinateSpace, canvasSize: CGSize) -> CGRect {
        space == .recording ? pictureRect : CGRect(origin: .zero, size: canvasSize)
    }

    func draw(
        space: RecordingOverlayCoordinateSpace,
        canvasSize: CGSize,
        in context: CGContext,
        content: (CGSize) -> Void
    ) {
        guard space == .recording else {
            content(canvasSize)
            return
        }
        guard pictureRect.width > 0, pictureRect.height > 0, opacity > 0.001 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: clippingRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        context.clip()
        context.setAlpha(opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: pictureRect.minX, y: pictureRect.minY)
        content(pictureRect.size)
        context.endTransparencyLayer()
    }

    static func convert(_ point: CGPoint, from source: CGRect, to destination: CGRect) -> CGPoint {
        CGPoint(
            x: (source.minX + point.x * source.width - destination.minX) / destination.width,
            y: (source.minY + point.y * source.height - destination.minY) / destination.height
        )
    }
}
