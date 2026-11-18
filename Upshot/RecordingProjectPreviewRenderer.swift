import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

nonisolated enum RecordingProjectPosterRevision {
    static func url(for session: RecordingSession) -> URL {
        session.directoryURL.appendingPathComponent("poster-revision.json")
    }

    static func value(for session: RecordingSession) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let editDocument = session.effectiveEditDocument()
        let document = (try? encoder.encode(editDocument)) ?? Data()
        let appearance = (try? encoder.encode(RecordingExportAppearanceStore.load(from: session.directoryURL))) ?? Data()
        let options = (try? encoder.encode(RecordingExportOptionStore.load(from: session.directoryURL))) ?? Data()
        let mediaDirectory = session.directoryURL.appendingPathComponent("media", isDirectory: true)
        var urls = [session.screenURL, session.cameraURL, session.captureManifestURL, session.pointerCaptureURL, mediaDirectory]
        if let cameraURL = editDocument?.cameraSource?.url(in: session.directoryURL) { urls.append(cameraURL) }
        if let background = editDocument?.style.value.background,
           case .customWallpaper(let wallpaper) = background { urls.append(wallpaper.url) }
        urls.append(contentsOf: (editDocument?.imageOverlays ?? []).map { mediaDirectory.appendingPathComponent($0.fileName) })
        let resources = urls
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return "\(url.lastPathComponent):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
            }.joined(separator: "|")
        return AppLog.identifier("composed-poster-v1:\(document.base64EncodedString()):\(appearance.base64EncodedString()):\(options.base64EncodedString()):\(resources)")
    }
}

actor RecordingProjectPreviewRenderer {
    private let configuration: RecordingStudioExporter.Configuration
    private let compositor: StudioFrameCompositor
    private let pool: CVPixelBufferPool
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let screenGenerator: AVAssetImageGenerator
    private let cameraGenerator: AVAssetImageGenerator?
    private let cameraDuration: TimeInterval
    private let redactions: RecordingRedactionFrameFilter?
    private let beauty: StudioCameraBeautyFrameFilter?
    private var cancelled = false
    private var wallpaperPrepared = false

    init(configuration: RecordingStudioExporter.Configuration, cameraDuration: TimeInterval = 0) throws {
        guard configuration.canvasSize.width.isFinite, configuration.canvasSize.height.isFinite,
              configuration.canvasSize.width > 0, configuration.canvasSize.height > 0 else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }
        self.configuration = configuration
        self.cameraDuration = cameraDuration
        let scale = min(1, 640 / max(configuration.canvasSize.width, configuration.canvasSize.height))
        let size = CGSize(
            width: max(2, (configuration.canvasSize.width * scale).rounded()),
            height: max(2, (configuration.canvasSize.height * scale).rounded())
        )
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, [
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()
        ] as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }
        self.pool = pool
        compositor = StudioFrameCompositor(
            canvasSize: size,
            videoCropRect: configuration.videoCropRect,
            style: configuration.style,
            cameraLayoutTimeline: configuration.cameraLayoutTimeline,
            viewportTimeline: configuration.viewportTimeline,
            pointerTimeline: configuration.pointerTimeline,
            showsPressEffects: configuration.showsPressEffects,
            clickEffectSettings: configuration.clickEffectSettings,
            keystrokeTimeline: configuration.keystrokeTimeline,
            keystrokePlacement: configuration.keystrokePlacement,
            keystrokeAppearance: configuration.appearance.keystrokes,
            shot: configuration.appearance.shot,
            speedBadgeTimeline: configuration.speedBadgeTimeline,
            speedBadgePlacement: configuration.speedBadgePlacement,
            subtitleTimeline: configuration.subtitleTimeline,
            subtitleStyle: configuration.subtitleStyle,
            captionTimeline: configuration.captionTimeline,
            captionCanvasSize: configuration.canvasSize,
            karaokeTimeline: configuration.karaokeTimeline,
            includeBubble: configuration.cameraURL != nil,
            cameraAspect: configuration.cameraAspect ?? RecordingCameraLayoutResolver.defaultCameraAspect,
            timing: RecordingExportTiming(settings: configuration.exportSettings, motionBlurLevel: configuration.deliveryOptions.motionBlurLevel),
            reframe: configuration.reframe,
            fitContentAspect: configuration.fitContentAspect,
            usesUniformPadding: configuration.usesUniformPadding,
            motionTimeline: configuration.motionTimeline,
            textOverlays: configuration.textOverlays,
            arrowOverlays: configuration.arrowOverlays,
            imageOverlays: configuration.imageOverlays,
            mediaDirectory: configuration.mediaDirectory
        )
        screenGenerator = Self.generator(url: configuration.screenURL)
        cameraGenerator = configuration.cameraURL.map(Self.generator(url:))
        redactions = RecordingRedactionFrameFilter(redactions: configuration.redactions)
        beauty = StudioCameraBeautyFrameFilter(beauty: configuration.style.camera.beauty)
    }

    func firstFrame() async throws -> CGImage {
        guard let location = configuration.clipTimeline.location(at: 0) else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }
        let image = try await screenGenerator.image(at: CMTime(seconds: location.sourceTime, preferredTimescale: 600)).image
        try checkCancellation()
        return try await render(screenFrame: CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer(image)), editorTime: 0)
    }

    func render(screenFrame: CVReadOnlyPixelBuffer, editorTime: TimeInterval) async throws -> CGImage {
        try checkCancellation()
        if !wallpaperPrepared {
            compositor.wallpaperVideo = try await StudioWallpaperVideoFrameSource.make(background: configuration.style.background)
            try checkCancellation()
            wallpaperPrepared = true
        }
        guard let location = configuration.clipTimeline.location(at: editorTime) else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }
        var camera: CVPixelBuffer?
        var cameraTime = max(0, location.sourceTime - configuration.cameraOffset)
        if cameraDuration > 0 {
            cameraTime = configuration.cameraLoops
                ? cameraTime.truncatingRemainder(dividingBy: cameraDuration)
                : min(cameraTime, max(0, cameraDuration - 1 / 600))
        }
        if let cameraGenerator {
            let image = try await cameraGenerator.image(at: CMTime(seconds: cameraTime, preferredTimescale: 600)).image
            try checkCancellation()
            let buffer = try pixelBuffer(image)
            camera = beauty?.apply(to: buffer, time: cameraTime) ?? buffer
        }
        return try screenFrame.withUnsafeBuffer { screenBuffer in
            try autoreleasepool {
                let screen = redactions?.apply(to: screenBuffer, atSourceTime: location.sourceTime) ?? screenBuffer
                let frame = try compositor.begin(
                    screenFrame: screen,
                    cameraFrame: camera,
                    cameraTime: cameraTime,
                    editorTime: editorTime,
                    sourceTime: location.sourceTime,
                    sourceRepeatsOnNextFrame: false,
                    pool: pool
                )
                try compositor.finish(frame)
                let image = CIImage(cvPixelBuffer: frame.destination)
                guard let result = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
                    throw RecordingStudioExporter.ExportError.writerFailed(nil)
                }
                return result
            }
        }
    }

    func cancel() {
        cancelled = true
        screenGenerator.cancelAllCGImageGeneration()
        cameraGenerator?.cancelAllCGImageGeneration()
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
    }

    private func pixelBuffer(_ image: CGImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()
        ] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }
        context.render(CIImage(cgImage: image), to: buffer, bounds: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)), colorSpace: colorSpace)
        return buffer
    }

    private nonisolated static func generator(url: URL) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }
}
