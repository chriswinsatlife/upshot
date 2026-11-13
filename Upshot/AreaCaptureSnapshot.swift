import AppKit
import ScreenCaptureKit

struct AreaCaptureSnapshot {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let image: CGImage

    var scale: CGFloat { CGFloat(image.width) / frame.width }

    func pixelPoint(at point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, floor((point.x - frame.minX) * scale)), CGFloat(image.width - 1)),
                y: min(max(0, floor((frame.maxY - point.y) * scale)), CGFloat(image.height - 1)))
    }

    func magnifierPixelRect(at point: CGPoint) -> CGRect {
        let pixel = pixelPoint(at: point)
        let side = min(17, CGFloat(min(image.width, image.height)))
        return CGRect(x: min(max(0, pixel.x - floor(side / 2)), CGFloat(image.width) - side),
                      y: min(max(0, pixel.y - floor(side / 2)), CGFloat(image.height) - side), width: side, height: side)
    }

    func magnifierSamplePosition(at point: CGPoint) -> CGPoint {
        let pixel = pixelPoint(at: point)
        let sample = magnifierPixelRect(at: point)
        return CGPoint(x: (pixel.x + 0.5 - sample.minX) / sample.width,
                       y: 1 - (pixel.y + 0.5 - sample.minY) / sample.height)
    }

    static func pixelAlignedRect(_ rect: CGRect, snapshots: [AreaCaptureSnapshot]) -> CGRect {
        let scale = snapshots.filter { $0.frame.intersects(rect) }.map(\.scale).max() ?? 1
        let x = floor(rect.minX * scale) / scale
        let y = floor(rect.minY * scale) / scale
        return CGRect(x: x, y: y, width: ceil(rect.maxX * scale) / scale - x, height: ceil(rect.maxY * scale) / scale - y)
    }

    static func captureAll() async throws -> [AreaCaptureSnapshot] {
        let lease = try await DesktopIconVisibilityService.shared.beginCapture()
        defer { DesktopIconVisibilityService.shared.endCapture(lease) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let coverIDs = DesktopIconVisibilityService.shared.coverWindowIDs
        let excluded = content.windows.filter {
            $0.owningApplication?.processID == getpid() && $0.windowLayer != 0 && !UpshotPreferences.includeAppWindowsInCaptures && !coverIDs.contains($0.windowID)
        }
        var snapshots: [AreaCaptureSnapshot] = []
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
            guard let displayID = ActiveDisplayResolver.displayID(for: screen) else { return nil }
            return (displayID, screen.frame)
        }
        for (displayID, frame) in screens {
            try Task.checkCancellation()
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CocoaError(.fileReadUnknown) }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            configuration.showsCursor = false
            configuration.ignoreShadowsDisplay = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
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
