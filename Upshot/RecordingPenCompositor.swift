import CoreGraphics
import CoreVideo
import Foundation

nonisolated struct RecordingPenStroke: Sendable {
    var points: [CGPoint]
    let lineWidth: CGFloat
}

nonisolated final class RecordingPenStrokeStore: @unchecked Sendable {
    static let shared = RecordingPenStrokeStore()

    private let lock = NSLock()
    private var strokes: [RecordingPenStroke] = []
    private var isDrawing = false

    var snapshot: [RecordingPenStroke] { lock.withLock { strokes } }

    func begin(at point: CGPoint, lineWidth: CGFloat) {
        lock.withLock {
            strokes.append(RecordingPenStroke(points: [point], lineWidth: lineWidth))
            isDrawing = true
        }
    }

    func append(_ point: CGPoint) {
        lock.withLock {
            guard isDrawing, !strokes.isEmpty else { return }
            strokes[strokes.count - 1].points.append(point)
        }
    }

    func end() {
        lock.withLock { isDrawing = false }
    }

    func clear() {
        lock.withLock {
            strokes.removeAll()
            isDrawing = false
        }
    }
}

nonisolated enum RecordingPenRenderer {
    static func draw(_ strokes: [RecordingPenStroke], in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.clip(to: rect)
        context.setStrokeColor(red: 1, green: 0.18, blue: 0.16, alpha: 1)
        context.setFillColor(red: 1, green: 0.18, blue: 0.16, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            guard let first = stroke.points.first else { continue }
            let width = stroke.lineWidth * rect.height
            context.setLineWidth(width)
            let origin = CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height)
            if stroke.points.count == 1 {
                context.fillEllipse(in: CGRect(x: origin.x - width / 2, y: origin.y - width / 2, width: width, height: width))
            } else {
                context.beginPath()
                context.move(to: origin)
                for point in stroke.points.dropFirst() {
                    context.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
                }
                context.strokePath()
            }
        }
        context.restoreGState()
    }
}

nonisolated enum RecordingPenCompositor {
    struct Failure: LocalizedError {
        let errorDescription: String? = "The live pen could not be written to the recording."
    }

    static func composite(
        _ source: CVPixelBuffer,
        strokes: [RecordingPenStroke],
        pool: CVPixelBufferPool?,
        contentRect: CGRect? = nil
    ) throws -> CVPixelBuffer {
        guard !strokes.isEmpty else { return source }
        guard let pool, CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else { throw Failure() }
        var destination: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination) == kCVReturnSuccess,
              let destination else { throw Failure() }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { throw Failure() }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { throw Failure() }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width == CVPixelBufferGetWidth(destination), height == CVPixelBufferGetHeight(destination),
              let sourceAddress = CVPixelBufferGetBaseAddress(source),
              let destinationAddress = CVPixelBufferGetBaseAddress(destination) else { throw Failure() }
        let sourceStride = CVPixelBufferGetBytesPerRow(source)
        let destinationStride = CVPixelBufferGetBytesPerRow(destination)
        for row in 0..<height {
            memcpy(destinationAddress.advanced(by: row * destinationStride), sourceAddress.advanced(by: row * sourceStride), width * 4)
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: destinationAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: destinationStride,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { throw Failure() }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        RecordingPenRenderer.draw(strokes, in: context, rect: contentRect ?? bounds)
        CVBufferPropagateAttachments(source, destination)
        return destination
    }
}
