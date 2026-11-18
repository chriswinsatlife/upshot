import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

nonisolated final class StudioWallpaperVideoFrameSource: @unchecked Sendable {
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let duration: TimeInterval
    private let transform: CGAffineTransform
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var current: (time: TimeInterval, image: CGImage)?
    private var next: CMSampleBuffer?
    private var previousTarget: TimeInterval?

    private init(asset: AVURLAsset, track: AVAssetTrack, duration: TimeInterval, transform: CGAffineTransform) {
        self.asset = asset
        self.track = track
        self.duration = duration
        self.transform = transform
    }

    static func make(background: AnnotationBackgroundStyle) async throws -> StudioWallpaperVideoFrameSource? {
        guard case .customWallpaper(let wallpaper) = background, wallpaper.isVideo else { return nil }
        do {
            let asset = AVURLAsset(url: wallpaper.url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                  let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw StudioWallpaperError.unreadableMedia
            }
            let transform = try await track.load(.preferredTransform)
            let source = StudioWallpaperVideoFrameSource(asset: asset, track: track, duration: duration, transform: transform)
            try source.restart()
            AppLog.event("rendering", "studio_wallpaper_video_decoder_ready", fields: ["duration": String(duration)])
            return source
        } catch {
            AppLog.event("rendering", "studio_wallpaper_video_decoder_failed", fields: ["error": AppLog.error(error)])
            throw error
        }
    }

    func image(at editorTime: TimeInterval) throws -> CGImage {
        do {
            let target = max(0, editorTime).truncatingRemainder(dividingBy: duration)
            if let previousTarget, target < previousTarget - 0.001 { try restart() }
            previousTarget = target
            while let sample = next {
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if time > target, current != nil { break }
                if let buffer = CMSampleBufferGetImageBuffer(sample) {
                    let image = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
                    guard let decoded = context.createCGImage(image, from: image.extent) else {
                        throw StudioWallpaperError.decoderFailed
                    }
                    current = (time, decoded)
                }
                next = output?.copyNextSampleBuffer()
            }
            if reader?.status == .failed { throw reader?.error ?? StudioWallpaperError.decoderFailed }
            guard let image = current?.image else { throw StudioWallpaperError.decoderFailed }
            return image
        } catch {
            AppLog.event("rendering", "studio_wallpaper_video_frame_failed", fields: ["error": AppLog.error(error)])
            throw error
        }
    }

    private func restart() throws {
        reader?.cancelReading()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw StudioWallpaperError.decoderFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? StudioWallpaperError.decoderFailed }
        self.reader = reader
        self.output = output
        current = nil
        next = output.copyNextSampleBuffer()
    }

    deinit { reader?.cancelReading() }
}
