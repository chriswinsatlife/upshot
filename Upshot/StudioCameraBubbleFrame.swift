import CoreGraphics
import AVFoundation
import CoreImage
import Foundation
import SwiftUI
import Synchronization

nonisolated enum RecordingCameraPreviewFrame: String, Codable, CaseIterable, Sendable {
    case legacy
    case standard
    case softBlur

    var title: String {
        switch self {
        case .legacy, .standard: "Standard"
        case .softBlur: "Soft blur"
        }
    }
}

nonisolated enum RecordingCameraZoomResponse: String, Codable, Sendable {
    case progress
    case magnification
}

nonisolated enum StudioCameraBubbleFrame {
    nonisolated final class Masks: NSObject, Sendable {
        let center: CGImage
        let edge: CGImage

        init(center: CGImage, edge: CGImage) {
            self.center = center
            self.edge = edge
        }
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let cache = Mutex<NSCache<NSString, Masks>>({
        let cache = NSCache<NSString, Masks>()
        cache.countLimit = 32
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }())

    static func feather(size: CGSize, canvasWidth: CGFloat) -> CGFloat {
        max(0, min(16 * canvasWidth / 1920, size.width / 8, size.height / 8))
    }

    static func rimWidth(size: CGSize) -> CGFloat {
        max(0, min(size.width, size.height)) / 300 * 0.75
    }

    static func path(in rect: CGRect, radius: CGFloat, squircle: CGFloat) -> CGPath {
        let r = max(0, min(radius, min(rect.width, rect.height) / 2))
        guard squircle > 0.001, r > 0 else {
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
        let exponent = 2 + 0.4 * min(max(squircle, 0), 1)
        let segments = min(96, max(8, Int(2 * ceil(sqrt(r)))))
        let path = CGMutablePath()
        for corner in 0..<4 {
            for index in 0...segments {
                let angle = CGFloat.pi / 2 * CGFloat(index) / CGFloat(segments)
                let u = index == 0 ? 0 : sin(angle)
                let v = index == segments ? 0 : cos(angle)
                let scale = r / pow(pow(u, exponent) + pow(v, exponent), 1 / exponent)
                let dx = u * scale, dy = v * scale
                let point: CGPoint = switch corner {
                case 0: CGPoint(x: rect.maxX - r + dx, y: rect.minY + r - dy)
                case 1: CGPoint(x: rect.maxX - r + dy, y: rect.maxY - r + dx)
                case 2: CGPoint(x: rect.minX + r - dx, y: rect.maxY - r + dy)
                default: CGPoint(x: rect.minX + r - dy, y: rect.minY + r - dx)
                }
                if corner == 0 && index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        return path
    }

    static func masks(size: CGSize, radius: CGFloat, squircle: CGFloat, inset: CGFloat) -> Masks? {
        guard size.width > 0, size.height > 0, inset > 0 else { return nil }
        let key = "\(size.width),\(size.height),\(radius),\(squircle),\(inset)" as NSString
        if let masks = cache.withLock({ $0.object(forKey: key) }) { return masks }
        let width = max(1, Int(ceil(size.width))), height = max(1, Int(ceil(size.height)))
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        func mask(distance: CGFloat) -> CGImage? {
            guard let bitmap = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            bitmap.setFillColor(CGColor(gray: 0, alpha: 1))
            bitmap.fill(extent)
            bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
            bitmap.addPath(path(in: CGRect(origin: .zero, size: size).insetBy(dx: distance, dy: distance),
                                radius: max(0, radius - distance), squircle: squircle))
            bitmap.fillPath()
            guard let image = bitmap.makeImage() else { return nil }
            let softened = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
                .clampedToExtent().applyingGaussianBlur(sigma: inset * 3 / 8).cropped(to: extent)
            return context.createCGImage(softened, from: extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
        }
        guard let center = mask(distance: inset * 2), let edge = mask(distance: inset) else {
            AppLog.event("rendering", "camera_bubble_mask_failed", fields: ["outcome": "failure"])
            return nil
        }
        let masks = Masks(center: center, edge: edge)
        cache.withLock { $0.setObject(masks, forKey: key, cost: width * height * 2) }
        return masks
    }

    static func soften(_ image: CGImage, size: CGSize, radius: CGFloat, squircle: CGFloat,
                       canvasWidth: CGFloat) -> CGImage? {
        let inset = feather(size: size, canvasWidth: canvasWidth)
        guard let masks = masks(size: size, radius: radius, squircle: squircle, inset: inset) else { return nil }
        let source = CIImage(cgImage: image)
        let extent = source.extent
        let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: inset * 3 / 8).cropped(to: extent)
        let center = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: CIImage(cgImage: masks.center, options: [.colorSpace: NSNull()])
        ])
        let result = center.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent),
            kCIInputMaskImageKey: CIImage(cgImage: masks.edge, options: [.colorSpace: NSNull()])
        ])
        guard let output = context.createCGImage(result, from: extent) else {
            AppLog.event("rendering", "camera_bubble_feather_failed", fields: ["outcome": "failure"])
            return nil
        }
        return output
    }
}

struct StudioCameraBubbleShape: Shape {
    var radius: CGFloat
    var squircle: CGFloat

    func path(in rect: CGRect) -> Path {
        if squircle <= 0.001 {
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
        return Path(StudioCameraBubbleFrame.path(in: rect, radius: radius, squircle: squircle))
    }
}

struct StudioCameraBubbleSurface: View {
    let size: CGSize
    let radius: CGFloat
    let squircle: CGFloat
    let frame: RecordingCameraPreviewFrame
    let canvasWidth: CGFloat
    let player: AVPlayer
    let sourceAspect: CGFloat
    let crop: CGRect

    var body: some View {
        let shape = frame == .legacy
            ? StudioCameraBubbleShape(radius: radius, squircle: squircle).path(in: CGRect(origin: .zero, size: size))
            : Path(StudioCameraBubbleFrame.path(in: CGRect(origin: .zero, size: size), radius: radius, squircle: squircle))
        Group {
            if frame == .softBlur {
                StudioCameraBubbleSoftBlurView(player: player, parameters: StudioCameraBubblePreviewParameters(
                    radius: radius, squircle: squircle, canvasWidth: canvasWidth, crop: crop
                ))
            } else {
                RecordingCameraPictureView(player: player, sourceAspect: sourceAspect, crop: crop)
                    .frame(width: size.width, height: size.height)
                    .clipShape(shape)
                    .overlay {
                        shape.stroke(.white.opacity(frame == .legacy ? 0.25 : 0.26),
                                     lineWidth: frame == .legacy ? 2 : StudioCameraBubbleFrame.rimWidth(size: size) * 2)
                            .clipShape(shape)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
    }

}
