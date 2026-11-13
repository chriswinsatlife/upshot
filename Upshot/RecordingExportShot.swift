import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

nonisolated enum RecordingExportShot: String, Codable, CaseIterable, Sendable {
    case flat = "Flat"
    case tiltLeft = "Tilt Left"
    case tiltRight = "Tilt Right"
    case tiltUp = "Tilt Up"
    case orbit = "Orbit"
}

nonisolated struct RecordingExportShotCorners: Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    var bounds: CGRect {
        let points = [topLeft, topRight, bottomLeft, bottomRight]
        let left = points.map(\.x).min() ?? 0
        let right = points.map(\.x).max() ?? 0
        let bottom = points.map(\.y).min() ?? 0
        let top = points.map(\.y).max() ?? 0
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
}

nonisolated enum RecordingExportShotGeometry {
    static func corners(shot: RecordingExportShot, card: CGRect, time: TimeInterval) -> RecordingExportShotCorners {
        let yaw: Double
        let pitch: Double
        switch shot {
        case .flat: yaw = 0; pitch = 0
        case .tiltLeft: yaw = -0.32; pitch = 0.1
        case .tiltRight: yaw = 0.32; pitch = 0.1
        case .tiltUp: yaw = 0; pitch = 0.32
        case .orbit:
            yaw = sin(time * .pi / 3) * 0.32
            pitch = cos(time * .pi / 3) * 0.16
        }
        let depth = max(card.width, card.height) * 2.5
        func projected(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let rotatedX = x * cos(yaw)
            let firstDepth = -x * sin(yaw)
            let rotatedY = y * cos(pitch) - firstDepth * sin(pitch)
            let rotatedDepth = y * sin(pitch) + firstDepth * cos(pitch)
            let perspective = depth / max(depth * 0.5, depth + rotatedDepth)
            return CGPoint(x: rotatedX * perspective, y: rotatedY * perspective)
        }
        let points = [
            projected(-card.width / 2, card.height / 2),
            projected(card.width / 2, card.height / 2),
            projected(-card.width / 2, -card.height / 2),
            projected(card.width / 2, -card.height / 2)
        ]
        let bounds = RecordingExportShotCorners(topLeft: points[0], topRight: points[1], bottomLeft: points[2], bottomRight: points[3]).bounds
        let fit = min(card.width / max(1, bounds.width), card.height / max(1, bounds.height)) * (shot == .flat ? 1 : 0.94)
        func placed(_ point: CGPoint) -> CGPoint {
            CGPoint(x: card.midX + (point.x - bounds.midX) * fit, y: card.midY + (point.y - bounds.midY) * fit)
        }
        return RecordingExportShotCorners(topLeft: placed(points[0]), topRight: placed(points[1]), bottomLeft: placed(points[2]), bottomRight: placed(points[3]))
    }
}

nonisolated final class RecordingExportShotRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func draw(
        shot: RecordingExportShot,
        card: CGRect,
        cornerRadius: CGFloat,
        canvasSize: CGSize,
        background: CGImage?,
        shadow: CGFloat,
        time: TimeInterval,
        in graphics: CGContext
    ) throws {
        guard shot != .flat, card.width >= 1, card.height >= 1 else { return }
        graphics.flush()
        guard let canvas = graphics.makeImage(),
              let crop = canvas.cropping(to: card.integral),
              let mask = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }
        let local = CGRect(x: 0, y: 0, width: crop.width, height: crop.height)
        mask.addPath(CGPath(roundedRect: local, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        mask.clip()
        mask.draw(crop, in: local)
        guard let image = mask.makeImage() else { throw RecordingStudioExporter.ExportError.writerFailed(nil) }
        let bottomLeftCard = CGRect(x: card.minX, y: canvasSize.height - card.maxY, width: card.width, height: card.height)
        let corners = RecordingExportShotGeometry.corners(shot: shot, card: bottomLeftCard, time: time)
        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = corners.topLeft
        filter.topRight = corners.topRight
        filter.bottomLeft = corners.bottomLeft
        filter.bottomRight = corners.bottomRight
        guard let transformed = filter.outputImage,
              let rendered = context.createCGImage(transformed, from: transformed.extent) else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }
        graphics.saveGState()
        graphics.setBlendMode(.copy)
        if let background { graphics.draw(background, in: CGRect(origin: .zero, size: canvasSize)) }
        else {
            graphics.setFillColor(CGColor(gray: 0, alpha: 1))
            graphics.fill(CGRect(origin: .zero, size: canvasSize))
        }
        graphics.setBlendMode(.normal)
        let blur = min(canvasSize.width, canvasSize.height) * 0.045 * shadow
        graphics.setShadow(offset: CGSize(width: 0, height: -blur * 0.35), blur: blur, color: CGColor(gray: 0, alpha: shadow * 0.55))
        graphics.draw(rendered, in: transformed.extent)
        graphics.restoreGState()
    }
}
