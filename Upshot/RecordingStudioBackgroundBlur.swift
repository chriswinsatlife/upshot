import CoreGraphics
import CoreImage
import Foundation
import ImageIO

nonisolated enum RecordingStudioBackgroundBlur {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    nonisolated(unsafe) private static let images = NSCache<NSString, CGImage>()

    static func wallpaper(at url: URL, canvasSize: CGSize, amount: CGFloat) -> CGImage? {
        let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        let modification = attributes?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let key = "\(url.path)|\(modification)|\(canvasSize.width)|\(canvasSize.height)|\(amount)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              let output = render(image, canvasSize: canvasSize, amount: amount) else {
            AppLog.event("rendering", "studio_background_blur_failed")
            return nil
        }
        images.totalCostLimit = 64 * 1024 * 1024
        images.setObject(output, forKey: key, cost: output.bytesPerRow * output.height)
        return output
    }

    static func render(_ image: CGImage, canvasSize: CGSize, amount: CGFloat) -> CGImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let blur = min(max(amount.isFinite ? amount : 0, 0), 8) * max(1, canvasSize.width) / 640
        let overscan = ceil(blur * 2)
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let sample = canvas.insetBy(dx: -overscan, dy: -overscan)
        let scale = max(sample.width / CGFloat(image.width), sample.height / CGFloat(image.height))
        let fill = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let placed = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: (canvas.width - fill.width) / 2,
                                              y: (canvas.height - fill.height) / 2))
            .clampedToExtent()
        let output = placed.applyingGaussianBlur(sigma: Double(blur)).cropped(to: canvas)
        return context.createCGImage(output, from: canvas)
    }
}
