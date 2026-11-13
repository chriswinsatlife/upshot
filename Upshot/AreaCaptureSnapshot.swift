import AppKit
import ScreenCaptureKit

struct AreaCaptureSnapshot {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let image: CGImage
    var presentationTime: TimeInterval?
    var pixelScale: CGFloat?
    var isCaptured = true

    var scale: CGFloat { pixelScale ?? CGFloat(image.width) / frame.width }
    var pixelWidth: Int { isCaptured ? image.width : Int(ceil(frame.width * scale)) }
    var pixelHeight: Int { isCaptured ? image.height : Int(ceil(frame.height * scale)) }

    func pixelPoint(at point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, floor((point.x - frame.minX) * scale)), CGFloat(pixelWidth - 1)),
                y: min(max(0, floor((frame.maxY - point.y) * scale)), CGFloat(pixelHeight - 1)))
    }

    func magnifierPixelRect(at point: CGPoint) -> CGRect {
        let pixel = pixelPoint(at: point)
        let side = min(17, CGFloat(min(pixelWidth, pixelHeight)))
        return CGRect(x: min(max(0, pixel.x - floor(side / 2)), CGFloat(pixelWidth) - side),
                      y: min(max(0, pixel.y - floor(side / 2)), CGFloat(pixelHeight) - side), width: side, height: side)
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

    static func geometry(displayID: CGDirectDisplayID, frame: CGRect, scale: CGFloat) throws -> AreaCaptureSnapshot {
        guard frame.width > 0, frame.height > 0, scale > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { throw CocoaError(.fileReadUnknown) }
        return AreaCaptureSnapshot(displayID: displayID, frame: frame, image: image, pixelScale: scale, isCaptured: false)
    }

    static func displayGeometry() throws -> [AreaCaptureSnapshot] {
        let geometry = try NSScreen.screens.compactMap { screen -> AreaCaptureSnapshot? in
            guard let displayID = ActiveDisplayResolver.displayID(for: screen) else { return nil }
            return try self.geometry(displayID: displayID, frame: screen.frame, scale: screen.backingScaleFactor)
        }
        guard !geometry.isEmpty else { throw CocoaError(.fileReadUnknown) }
        return geometry
    }

    static func captureAll(desktopIconsPrepared: Bool = false, content: SCShareableContent? = nil) async throws -> [AreaCaptureSnapshot] {
        let lease = desktopIconsPrepared ? nil : try await DesktopIconVisibilityService.shared.beginCapture()
        defer { DesktopIconVisibilityService.shared.endCapture(lease) }
        let availableContent: SCShareableContent
        if let content { availableContent = content }
        else { availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        var snapshots: [AreaCaptureSnapshot] = []
        for geometry in try displayGeometry() {
            try Task.checkCancellation()
            snapshots.append(try await capture(geometry, content: availableContent))
        }
        guard !snapshots.isEmpty else { throw CocoaError(.fileReadUnknown) }
        return snapshots
    }

    static func capture(_ geometry: AreaCaptureSnapshot, in rect: CGRect? = nil, content: SCShareableContent) async throws -> AreaCaptureSnapshot {
        guard let display = content.displays.first(where: { $0.displayID == geometry.displayID }) else { throw CocoaError(.fileReadUnknown) }
        let filter = AreaCaptureWindowFilter.displayFilter(display: display, content: content)
        let region = rect.map { geometry.frame.intersection($0) } ?? geometry.frame
        guard !region.isNull, region.width >= 1, region.height >= 1 else { throw CocoaError(.fileReadCorruptFile) }
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: region.minX - geometry.frame.minX, y: geometry.frame.maxY - region.maxY,
                                          width: region.width, height: region.height)
        configuration.width = Int(ceil(region.width * scale))
        configuration.height = Int(ceil(region.height * scale))
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        let sample = try await SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: configuration)
        return AreaCaptureSnapshot(displayID: geometry.displayID, frame: region, image: try AreaCaptureFrameStream.image(from: sample),
                                   presentationTime: AreaCaptureFrameStream.presentationTime(of: sample), pixelScale: scale)
    }

    static func acquireSelection(_ geometry: [AreaCaptureSnapshot], in rect: CGRect, retained: [CGDirectDisplayID: AreaCaptureSnapshot],
                                 capture: (AreaCaptureSnapshot, CGRect) async throws -> AreaCaptureSnapshot) async throws -> [AreaCaptureSnapshot] {
        var selected: [AreaCaptureSnapshot] = []
        for display in geometry where display.frame.intersects(rect) {
            try Task.checkCancellation()
            if let frame = retained[display.displayID] { selected.append(frame) }
            else { selected.append(try await capture(display, rect)) }
        }
        guard !selected.isEmpty else { throw CocoaError(.fileReadUnknown) }
        return selected
    }

    static func composite(_ snapshots: [AreaCaptureSnapshot], in rect: CGRect) throws -> CGImage {
        let intersecting = snapshots.filter { $0.frame.intersects(rect) }
        guard rect.width >= 1, rect.height >= 1, intersecting.allSatisfy(\.isCaptured), let scale = intersecting.map(\.scale).max(),
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
