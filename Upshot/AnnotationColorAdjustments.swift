import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

nonisolated struct AnnotationColorAdjustments: Codable, Equatable, Sendable {
    var exposure: CGFloat = 0
    var contrast: CGFloat = 1
    var saturation: CGFloat = 1
    var temperature: CGFloat = 0

    var isDefault: Bool { self == AnnotationColorAdjustments() }
}

nonisolated enum AnnotationColorProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ image: CGImage, settings: AnnotationColorAdjustments) throws -> CGImage {
        guard !settings.isDefault else { return image }
        let input = CIImage(cgImage: image)
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = input
        exposure.ev = Float(min(3, max(-3, settings.exposure)))
        let controls = CIFilter.colorControls()
        controls.inputImage = exposure.outputImage
        controls.contrast = Float(min(2, max(0, settings.contrast)))
        controls.saturation = Float(min(2, max(0, settings.saturation)))
        let temperature = CIFilter.temperatureAndTint()
        temperature.inputImage = controls.outputImage
        temperature.neutral = CIVector(x: 6500, y: 0)
        temperature.targetNeutral = CIVector(x: 6500 - min(100, max(-100, settings.temperature)) * 30, y: 0)
        guard let output = temperature.outputImage,
              let result = context.createCGImage(output, from: input.extent, format: .RGBA8,
                                                 colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB()) else {
            throw CocoaError(.coderInvalidValue)
        }
        return result
    }
}
