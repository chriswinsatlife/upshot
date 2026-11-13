import AppKit
import CoreGraphics
import Foundation

nonisolated struct ScreenshotCursorSnapshot: Sendable {
    let image: CGImage
    let pointSize: CGSize
    let hotSpot: CGPoint
    let location: CGPoint
}

enum ScreenshotCursorService {
    static func snapshot(at location: CGPoint? = nil) -> ScreenshotCursorSnapshot? {
        guard UpshotPreferences.screenshotShowCursor else { return nil }
        let cursor = NSCursor.currentSystem ?? NSCursor.arrow
        let image = cursor.image
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let pixels = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let point = location ?? CGEvent(source: nil)?.location else { return nil }
        return ScreenshotCursorSnapshot(
            image: pixels,
            pointSize: image.size,
            hotSpot: cursor.hotSpot,
            location: point
        )
    }

    static var noninteractiveCaptureArguments: [String] {
        UpshotPreferences.screenshotShowCursor ? ["-C"] : []
    }

    nonisolated static func composite(
        image: CGImage,
        cursor: ScreenshotCursorSnapshot,
        captureBounds: CGRect
    ) throws -> CGImage {
        guard captureBounds.width > 0, captureBounds.height > 0,
              captureBounds.contains(cursor.location) else {
            AppLog.event("capture", "screenshot_output_cursor_omitted_outside_capture_bounds")
            return image
        }
        let scaleX = CGFloat(image.width) / captureBounds.width
        let scaleY = CGFloat(image.height) / captureBounds.height
        let rect = CGRect(
            x: (cursor.location.x - captureBounds.minX - cursor.hotSpot.x) * scaleX,
            y: CGFloat(image.height) - (cursor.location.y - captureBounds.minY - cursor.hotSpot.y + cursor.pointSize.height) * scaleY,
            width: cursor.pointSize.width * scaleX,
            height: cursor.pointSize.height * scaleY
        )
        let context = try ScreenshotPixelProcessor.bitmapContext(
            width: image.width,
            height: image.height,
            colorSpace: ScreenshotPixelProcessor.colorSpace(for: image)
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(cursor.image, in: rect)
        guard let result = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        AppLog.event("capture", "screenshot_output_cursor_composited", fields: ["x": String(describing: rect.minX), "y": String(describing: rect.minY)])
        return result
    }
}
