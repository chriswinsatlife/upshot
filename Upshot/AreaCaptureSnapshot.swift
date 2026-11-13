import AppKit
import ScreenCaptureKit

struct AreaCaptureSnapshot {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let image: CGImage

    var scale: CGFloat { CGFloat(image.width) / frame.width }

    static func captureAll() async throws -> [AreaCaptureSnapshot] {
        var snapshots: [AreaCaptureSnapshot] = []
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
            guard let displayID = ActiveDisplayResolver.displayID(for: screen) else { return nil }
            return (displayID, screen.frame)
        }
        for (displayID, frame) in screens {
            try Task.checkCancellation()
            let image = try await SCScreenshotManager.captureImage(in: CGDisplayBounds(displayID))
            snapshots.append(AreaCaptureSnapshot(displayID: displayID, frame: frame, image: image))
        }
        guard !snapshots.isEmpty else { throw CocoaError(.fileReadUnknown) }
        return snapshots
    }

    static func composite(_ snapshots: [AreaCaptureSnapshot], in rect: CGRect) throws -> CGImage {
        let intersecting = snapshots.filter { $0.frame.intersects(rect) }
        guard rect.width >= 1, rect.height >= 1, let scale = intersecting.map(\.scale).max(),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(ceil(rect.width * scale)), height: Int(ceil(rect.height * scale)),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        for snapshot in intersecting {
            context.saveGState()
            context.clip(to: snapshot.frame.intersection(rect))
            context.draw(snapshot.image, in: snapshot.frame)
            context.restoreGState()
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        NSLog("Area composition completed: displays=%ld pixels=%ldx%ld scale=%.2f", intersecting.count, image.width, image.height, scale)
        return image
    }
}
