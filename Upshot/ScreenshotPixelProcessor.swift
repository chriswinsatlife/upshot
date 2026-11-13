import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ScreenshotPixelOptions: Sendable {
    var convertToSRGB = false
}

nonisolated struct ScreenshotPixelProcessingResult: Sendable {
    let width: Int
    let height: Int
    let sourceScale: CGFloat
    let outputScale: CGFloat
}

nonisolated enum ScreenshotPixelProcessor {
    static func processFile(
        at url: URL,
        sourceScale: CGFloat? = nil,
        options: ScreenshotPixelOptions
    ) throws -> ScreenshotPixelProcessingResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let scale = sourceScale.flatMap { $0.isFinite && $0 >= 1 ? $0 : nil }
            ?? max(1, dpi / 72)
        let outputImage = try process(image: image, options: options)
        try writePNG(outputImage, to: url, scale: scale)
        return ScreenshotPixelProcessingResult(
            width: outputImage.width,
            height: outputImage.height,
            sourceScale: scale,
            outputScale: scale
        )
    }

    static func process(image: CGImage, options: ScreenshotPixelOptions) throws -> CGImage {
        guard options.convertToSRGB else { return image }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let context = try bitmapContext(width: image.width, height: image.height, colorSpace: colorSpace)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        NSLog("Screenshot output: sRGB conversion completed")
        return converted
    }

    static func writePNG(_ image: CGImage, to url: URL, scale: CGFloat) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: url, options: .atomic)
    }

    static func bitmapContext(width: Int, height: Int, colorSpace: CGColorSpace) throws -> CGContext {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.interpolationQuality = .high
        return context
    }

    static func colorSpace(for image: CGImage) -> CGColorSpace {
        if let colorSpace = image.colorSpace, colorSpace.model == .rgb { return colorSpace }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }
}
