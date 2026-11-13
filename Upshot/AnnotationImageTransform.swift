import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum AnnotationImageTransform: String, CaseIterable, Identifiable {
    case rotateClockwise
    case rotateCounterclockwise
    case flipHorizontal
    case flipVertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rotateClockwise: "Rotate Clockwise"
        case .rotateCounterclockwise: "Rotate Counterclockwise"
        case .flipHorizontal: "Flip Horizontally"
        case .flipVertical: "Flip Vertically"
        }
    }

    var orientation: CGImagePropertyOrientation {
        switch self {
        case .rotateClockwise: .right
        case .rotateCounterclockwise: .left
        case .flipHorizontal: .upMirrored
        case .flipVertical: .downMirrored
        }
    }

    func pageTransform(for size: CGSize) -> CGAffineTransform {
        switch self {
        case .rotateClockwise: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)
        case .rotateCounterclockwise: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: size.width)
        case .flipHorizontal: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0)
        case .flipVertical: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        }
    }
}

nonisolated enum AnnotationImageFileProcessor {
    struct Result: Sendable {
        let url: URL
        let size: CGSize
    }

    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: rawOrientation), orientation != .up else { return image }
        let oriented = CIImage(cgImage: image).oriented(orientation)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let result = context.createCGImage(oriented, from: oriented.extent, format: .RGBA8,
                                                colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB()) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }

    static func write(_ image: CGImage) throws -> Result {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Upshot_ImageEdit_\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return Result(url: url, size: CGSize(width: image.width, height: image.height))
    }

    static func transform(_ url: URL, operation: AnnotationImageTransform) throws -> Result {
        let source = try load(url)
        let transformed = CIImage(cgImage: source).oriented(operation.orientation)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let image = context.createCGImage(transformed, from: transformed.extent, format: .RGBA8,
                                               colorSpace: source.colorSpace ?? CGColorSpaceCreateDeviceRGB()) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try write(image)
    }
}
