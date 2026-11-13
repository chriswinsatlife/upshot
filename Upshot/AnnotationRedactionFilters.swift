import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

nonisolated enum AnnotationRedactionFilters {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ image: CGImage, kind: RedactionKind, density: Double, scale: Double = 1) -> CGImage? {
        let input = CIImage(cgImage: image)
        let clamped = input.clampedToExtent()
        let strength = min(1, max(0, density))
        let radius = Float((2 + strength * 28) * scale)
        let block = Float((4 + strength * 36) * scale)
        let center = CGPoint(x: input.extent.midX, y: input.extent.midY)
        let output: CIImage?
        switch kind {
        case .blur:
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = clamped
            filter.radius = radius
            output = filter.outputImage
        case .pixelate:
            let filter = CIFilter.pixellate()
            filter.inputImage = clamped
            filter.scale = max(1, block)
            filter.center = center
            output = filter.outputImage
        case .box:
            let filter = CIFilter.boxBlur()
            filter.inputImage = clamped
            filter.radius = radius
            output = filter.outputImage
        case .disc:
            let filter = CIFilter.discBlur()
            filter.inputImage = clamped
            filter.radius = radius
            output = filter.outputImage
        case .motionHorizontal, .motionVertical:
            let filter = CIFilter.motionBlur()
            filter.inputImage = clamped
            filter.radius = radius * 2
            filter.angle = kind == .motionHorizontal ? 0 : .pi / 2
            output = filter.outputImage
        case .zoom:
            let filter = CIFilter.zoomBlur()
            filter.inputImage = clamped
            filter.center = center
            filter.amount = Float(5 + strength * 55)
            output = filter.outputImage
        case .hexagonal:
            let filter = CIFilter.hexagonalPixellate()
            filter.inputImage = clamped
            filter.center = center
            filter.scale = max(1, block)
            output = filter.outputImage
        }
        guard let output else { return nil }
        return context.createCGImage(output.cropped(to: input.extent), from: input.extent)
    }
}
