import AVFoundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum RecordingGIFExporter {
    static let maximumGIFFrameDelay: Double = 600

    enum ExportError: LocalizedError {
        case destinationUnavailable
        case encodingFailed
        case invalidDuration

        var errorDescription: String? {
            switch self {
            case .destinationUnavailable: "The GIF destination could not be created."
            case .encodingFailed: "The animated GIF could not be encoded."
            case .invalidDuration: "The recording has no exportable duration."
            }
        }
    }

    @concurrent
    static func export(
        videoURL: URL,
        options: RecordingExportDeliveryOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            AppLog.event("recording", "gif_export_failed", fields: ["stage": "duration"])
            throw ExportError.invalidDuration
        }
        let outputURL = videoURL.deletingPathExtension().appendingPathExtension("gif")
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, 0, nil) else {
            AppLog.event("recording", "gif_export_failed", fields: ["stage": "destination"])
            throw ExportError.destinationUnavailable
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: options.effectiveGIFLoops ? 0 : 1]
        ] as CFDictionary)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let context = CIContext(options: [.cacheIntermediates: false])
        let frameRate = Double(options.gifFrameRate.rawValue)
        let frameCount = max(1, Int(ceil(duration * frameRate)))
        var previous: CGImage?
        var previousData: Data?
        var accumulatedDuration: Double = 0
        var emittedFrames = 0
        var encodedDuration: Double = 0
        var elapsedDuration: Double = 0
        func append(_ image: CGImage, duration: Double) {
            elapsedDuration += duration
            let end = (elapsedDuration * 100).rounded() / 100
            let delay = max(0.01, end - encodedDuration)
            encodedDuration += delay
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ] as CFDictionary)
            emittedFrames += 1
        }
        do {
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let time = Double(index) / frameRate
                let extracted = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000)).image
                let image: CGImage = try autoreleasepool {
                    let source = CIImage(cgImage: extracted)
                    let size = (options.gifSize ?? .original).outputSize(for: source.extent.size)
                    var resized = source
                    if size != source.extent.size {
                        let resizer = CIFilter.lanczosScaleTransform()
                        resizer.inputImage = source
                        resizer.scale = Float(size.height / source.extent.height)
                        resizer.aspectRatio = Float((size.width / source.extent.width) / (size.height / source.extent.height))
                        guard let result = resizer.outputImage else { throw ExportError.encodingFailed }
                        resized = result
                    }
                    let filter = CIFilter.colorPosterize()
                    filter.inputImage = resized
                    filter.levels = options.gifQuality.colorLevels
                    guard let filtered = filter.outputImage,
                          let rendered = context.createCGImage(filtered, from: CGRect(origin: .zero, size: size)) else {
                        throw ExportError.encodingFailed
                    }
                    return rendered
                }
                let frameDuration = min(1 / frameRate, duration - time)
                let data = options.optimizesGIF ? image.dataProvider?.data.map { $0 as Data } : nil
                if options.optimizesGIF, let previousData, let data, previousData == data {
                    if accumulatedDuration + frameDuration > Self.maximumGIFFrameDelay, let previous {
                        append(previous, duration: accumulatedDuration)
                        accumulatedDuration = 0
                    }
                    accumulatedDuration += frameDuration
                } else {
                    if let previous { append(previous, duration: accumulatedDuration) }
                    previous = image
                    previousData = data
                    accumulatedDuration = frameDuration
                }
                progress(min(0.99, Double(index + 1) / Double(frameCount)))
            }
            if let previous { append(previous, duration: accumulatedDuration) }
            guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
            AppLog.event("recording", "gif_export_completed", fields: [
                "duration": String(encodedDuration), "fps": String(options.gifFrameRate.rawValue),
                "frames": String(emittedFrames), "optimized": String(options.optimizesGIF),
                "quality": options.gifQuality.rawValue, "sourceFrames": String(frameCount),
                "loops": String(options.effectiveGIFLoops), "size": options.gifSize?.rawValue ?? "legacy",
                "width": String(previous?.width ?? 0), "height": String(previous?.height ?? 0)
            ])
            progress(1)
            return outputURL
        } catch {
            AppLog.event("recording", "gif_export_failed", fields: ["stage": "encoding", "error": AppLog.error(error)])
            generator.cancelAllCGImageGeneration()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
