import CoreGraphics
import Foundation

nonisolated enum AnnotationImageCombination: String, CaseIterable, Identifiable {
    case sideBySide
    case stacked

    var id: String { rawValue }
    var title: String { self == .sideBySide ? "Add Image Side by Side…" : "Add Image Stacked…" }
}

extension AnnotationImageFileProcessor {
    nonisolated static func combine(_ sourceURL: URL, with additionalURL: URL, layout: AnnotationImageCombination) throws -> Result {
        let first = try load(sourceURL)
        let second = try load(additionalURL)
        let width = layout == .sideBySide ? first.width + second.width : max(first.width, second.width)
        let height = layout == .stacked ? first.height + second.height : max(first.height, second.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: first.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.interpolationQuality = .none
        context.draw(first, in: CGRect(x: 0, y: height - first.height, width: first.width, height: first.height))
        context.draw(second, in: CGRect(x: layout == .sideBySide ? first.width : 0,
                                       y: layout == .sideBySide ? height - second.height : 0,
                                       width: second.width, height: second.height))
        guard let output = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return try write(output)
    }
}
