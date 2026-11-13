import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ScreenshotPixelOptions: Sendable {
    var convertToSRGB = false
    var scaleToOneX = false
    var addBorder = false
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
        let scale = Self.sourceScale(properties: properties, override: sourceScale)
        let outputScale: CGFloat = options.scaleToOneX ? 1 : scale
        var outputImage = try convertAndScale(image: image, sourceScale: scale, options: options)
        if options.addBorder { outputImage = try addingBorder(to: outputImage) }
        try writePNG(outputImage, to: url, scale: outputScale, backgroundPresetApplied: ScreenshotOutputMetadata.hasAppliedBackgroundPreset(properties: properties))
        return ScreenshotPixelProcessingResult(
            width: outputImage.width,
            height: outputImage.height,
            sourceScale: scale,
            outputScale: outputScale
        )
    }

    static func sourceScale(properties: [CFString: Any], override: CGFloat?) -> CGFloat {
        if let override, override.isFinite, override >= 1 { return override }
        let dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        return dpi.isFinite ? max(1, dpi / 72) : 1
    }

    static func convertAndScale(image: CGImage, sourceScale: CGFloat = 1, options: ScreenshotPixelOptions) throws -> CGImage {
        let scale = options.scaleToOneX && sourceScale.isFinite ? max(1, sourceScale) : 1
        guard options.convertToSRGB || scale > 1 else { return image }
        let colorSpace = options.convertToSRGB
            ? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            : colorSpace(for: image)
        let width = max(1, Int((CGFloat(image.width) / scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) / scale).rounded()))
        let context = try bitmapContext(width: width, height: height, colorSpace: colorSpace)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let converted = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        if options.convertToSRGB { AppLog.event("capture", "screenshot_output_srgb_conversion_completed") }
        if scale > 1 { AppLog.event("capture", "screenshot_output_retina_1x_scaling_completed", fields: ["height": String(describing: height), "width": String(describing: width)]) }
        return converted
    }

    static func writePNG(_ image: CGImage, to url: URL, scale: CGFloat, backgroundPresetApplied: Bool = false) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * scale,
            kCGImagePropertyDPIHeight: 72 * scale
        ]
        if backgroundPresetApplied {
            properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: ScreenshotOutputMetadata.backgroundPresetDescription]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: url, options: .atomic)
    }

    static func addingBorder(to image: CGImage) throws -> CGImage {
        let width = image.width + 2
        let height = image.height + 2
        let context = try bitmapContext(width: width, height: height, colorSpace: colorSpace(for: image))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.clear(CGRect(x: 1, y: 1, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 1, y: 1, width: image.width, height: image.height))
        guard let bordered = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        AppLog.event("capture", "screenshot_output_1px_border_completed", fields: ["height": String(describing: height), "width": String(describing: width)])
        return bordered
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
