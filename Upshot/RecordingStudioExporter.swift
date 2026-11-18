
import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import VideoToolbox

nonisolated final class RecordingStudioExporter: @unchecked Sendable {
    struct Configuration: Sendable {
        let screenURL: URL
        let cameraURL: URL?
        let cameraOffset: TimeInterval
        let cameraAspect: CGFloat?
        let style: RecordingStudioStyle
        let cameraLayoutTimeline: RecordingCameraLayoutTimeline
        let viewportTimeline: ViewportTimeline
        let pointerTimeline: PointerTimeline?
        let showsPressEffects: Bool
        let clickEffectSettings: RecordingClickEffectSettings
        let keystrokeTimeline: KeystrokeCaptionTimeline?
        let keystrokePlacement: RecordingKeystrokePlacement
        let speedBadgeTimeline: SpeedBadgeTimeline?
        let speedBadgePlacement: RecordingKeystrokePlacement
        let subtitleTimeline: SubtitleTimeline?
        let subtitleStyle: SubtitleBarStyle
        let captionTimeline: StudioCaptionTimeline?
        let karaokeTimeline: KaraokeTimeline?
        let canvasSize: CGSize
        let videoCropRect: CGRect
        let clipTimeline: RecordingClipTimeline
        var exportSettings: VideoCompressionSettings
        var appearance = RecordingExportAppearance()
        var deliveryOptions = RecordingExportDeliveryOptions()
        var sourcePixelScale: Double = 1
        var recordedAudioTrackNames: [String] = []
        var cameraLoops = false
        var growingUploadSource: GrowingCloudUploadSource?
        let audioReplacementURL: URL?
        let audioVolume: Double
        let reframe: ReframeTrack?
        let fitContentAspect: CGFloat?
        let usesUniformPadding: Bool
        let motionTimeline: RecordingStudioMotionTimeline
        var textOverlays: [RecordingTextOverlay] = []
        var redactions: [RecordingRedaction] = []
        var arrowOverlays: [RecordingArrowOverlay] = []
        var imageOverlays: [RecordingImageOverlay] = []
        var audioClips: [RecordingAudioClip] = []
        var mediaDirectory: URL?

        init(
            screenURL: URL,
            cameraURL: URL?,
            cameraOffset: TimeInterval,
            cameraAspect: CGFloat? = nil,
            style: RecordingStudioStyle,
            cameraLayoutTimeline: RecordingCameraLayoutTimeline,
            viewportTimeline: ViewportTimeline,
            pointerTimeline: PointerTimeline?,
            showsPressEffects: Bool,
            clickEffectSettings: RecordingClickEffectSettings = RecordingClickEffectSettings(),
            keystrokeTimeline: KeystrokeCaptionTimeline?,
            keystrokePlacement: RecordingKeystrokePlacement,
            speedBadgeTimeline: SpeedBadgeTimeline? = nil,
            speedBadgePlacement: RecordingKeystrokePlacement = .topRight,
            subtitleTimeline: SubtitleTimeline?,
            subtitleStyle: SubtitleBarStyle,
            captionTimeline: StudioCaptionTimeline? = nil,
            karaokeTimeline: KaraokeTimeline? = nil,
            canvasSize: CGSize,
            videoCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
            clipTimeline: RecordingClipTimeline,
            exportSettings: VideoCompressionSettings,
            audioReplacementURL: URL? = nil,
            audioVolume: Double = 1,
            reframe: ReframeTrack? = nil,
            fitContentAspect: CGFloat? = nil,
            usesUniformPadding: Bool = false,
            motionTimeline: RecordingStudioMotionTimeline = .none,
            textOverlays: [RecordingTextOverlay] = [],
            redactions: [RecordingRedaction] = [],
            arrowOverlays: [RecordingArrowOverlay] = [],
            imageOverlays: [RecordingImageOverlay] = [],
            audioClips: [RecordingAudioClip] = [],
            mediaDirectory: URL? = nil
        ) {
            self.screenURL = screenURL
            self.cameraURL = cameraURL
            self.cameraOffset = cameraOffset
            self.cameraAspect = cameraAspect
            self.style = style
            self.cameraLayoutTimeline = cameraLayoutTimeline
            self.viewportTimeline = viewportTimeline
            self.pointerTimeline = style.hidesCursor ? nil : pointerTimeline
            self.showsPressEffects = showsPressEffects
            self.clickEffectSettings = clickEffectSettings.normalized
            self.keystrokeTimeline = keystrokeTimeline
            self.keystrokePlacement = keystrokePlacement
            self.speedBadgeTimeline = speedBadgeTimeline
            self.speedBadgePlacement = speedBadgePlacement
            self.subtitleTimeline = subtitleTimeline
            self.subtitleStyle = subtitleStyle
            self.captionTimeline = captionTimeline
            self.karaokeTimeline = karaokeTimeline
            self.canvasSize = canvasSize
            self.videoCropRect = videoCropRect
            self.clipTimeline = clipTimeline
            self.exportSettings = exportSettings
            self.audioReplacementURL = audioReplacementURL
            self.audioVolume = audioVolume
            self.reframe = reframe
            self.fitContentAspect = fitContentAspect
            self.usesUniformPadding = usesUniformPadding
            self.motionTimeline = motionTimeline
            self.textOverlays = textOverlays
            self.redactions = redactions
            self.arrowOverlays = arrowOverlays
            self.imageOverlays = imageOverlays
            self.audioClips = audioClips
            self.mediaDirectory = mediaDirectory
        }
    }

    enum ExportError: LocalizedError {
        case noVideoTrack
        case writerFailed(Error?)
        case cancelled
        case invalidResolution

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                "The recording has no video track."
            case .writerFailed(let error):
                error?.localizedDescription ?? "Writing the exported video failed."
            case .cancelled:
                "Export cancelled."
            case .invalidResolution:
                "Enter even dimensions between 2 and 8192 pixels."
            }
        }
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.withLock { cancelled = true }
        }

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }
    }

    @concurrent
    func export(
        _ configuration: Configuration,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let cancelFlag = CancelFlag()
        let started = CFAbsoluteTimeGetCurrent()
        return try await withTaskCancellationHandler {
            let makesGIF = configuration.deliveryOptions.format == .gif
            var rendering = configuration
            if makesGIF { rendering.exportSettings.removeAudio = true }
            let videoURL = try await run(rendering, cancelFlag: cancelFlag) { value in
                progress(value * (makesGIF ? 0.75 : 1))
            }
            let result: URL
            if makesGIF {
                defer { try? FileManager.default.removeItem(at: videoURL) }
                result = try await RecordingGIFExporter.export(videoURL: videoURL, options: configuration.deliveryOptions) { value in
                    progress(0.75 + value * 0.25)
                }
            } else {
                result = videoURL
            }
            AppLog.event("recording", "recording_export_completed", fields: ["format": String(describing: configuration.deliveryOptions.format.rawValue), "seconds": String(describing: CFAbsoluteTimeGetCurrent() - started)])
            return result
        } onCancel: {
            cancelFlag.cancel()
        }
    }

    private func run(
        _ configuration: Configuration,
        cancelFlag: CancelFlag,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        AppLog.event("recording", "export_appearance", fields: ["keystrokeFilter": String(describing: configuration.appearance.keystrokes.filter.rawValue), "keystrokePosition": String(describing: configuration.appearance.keystrokes.resolvedPosition(fallback: configuration.keystrokePlacement).rawValue), "keystrokeSize": String(describing: configuration.appearance.keystrokes.size.rawValue), "keystrokeStyle": String(describing: configuration.appearance.keystrokes.style.rawValue), "reframe": String(describing: String(configuration.reframe != nil)), "shot": String(describing: configuration.appearance.shot.rawValue), "zoom": String(describing: configuration.appearance.zoomAnimationStyle.rawValue)])
        let timing = RecordingExportTiming(
            settings: configuration.exportSettings,
            motionBlurLevel: configuration.deliveryOptions.motionBlurLevel,
            frameRateOverride: configuration.deliveryOptions.format == .gif ? Double(configuration.deliveryOptions.gifFrameRate.rawValue) : nil
        )
        let sourceAsset = AVURLAsset(url: configuration.screenURL)
        let wallpaperVideo = try await StudioWallpaperVideoFrameSource.make(background: configuration.style.background)
        let sourceDuration = try await sourceAsset.load(.duration).seconds
        let clipTimeline = configuration.clipTimeline.normalized(to: sourceDuration)
        guard clipTimeline.duration >= RecordingClipSegment.minimumDuration else {
            throw VideoTrimExportError.invalidRange
        }
        let screenAsset = try await RecordingCompositionBuilder.makeAsset(
            from: sourceAsset,
            tracks: sourceAsset.load(.tracks),
            timeline: clipTimeline,
            sourceDuration: sourceDuration
        )
        guard let videoTrack = try await screenAsset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let audioTracks = try await screenAsset.loadTracks(withMediaType: .audio)
        let exportStartTime = CMTime.zero
        let exportTimeRange = CMTimeRange(
            start: exportStartTime,
            duration: CMTime(seconds: clipTimeline.duration, preferredTimescale: 600)
        )

        let pixelScale = configuration.deliveryOptions.scalesRetinaToOne && configuration.sourcePixelScale.isFinite
            ? max(1, configuration.sourcePixelScale) : 1
        let sourceSize = CGSize(width: configuration.canvasSize.width / pixelScale, height: configuration.canvasSize.height / pixelScale)
        let outputSize: CGSize
        if configuration.deliveryOptions.format == .gif, let size = configuration.deliveryOptions.gifSize {
            outputSize = size.outputSize(for: sourceSize)
        } else {
            var settings = configuration.exportSettings
            if configuration.deliveryOptions.format == .gif { settings.resolutionUsesLongestEdge = false }
            outputSize = try Self.outputSize(source: sourceSize, settings: settings)
        }
        let canvasWidth = max(2, Int(outputSize.width.rounded()) & ~1)
        let canvasHeight = max(2, Int(outputSize.height.rounded()) & ~1)
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        AppLog.event("recording", "retina_export", fields: ["fps": String(describing: timing.framesPerSecond), "motionBlur": String(describing: timing.motionBlurLevel.rawValue), "width": String(describing: canvasWidth), "scale": String(describing: pixelScale), "height": String(describing: canvasHeight)])

        let screenReader = try AVAssetReader(asset: screenAsset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        videoOutput.alwaysCopiesSampleData = false
        screenReader.add(videoOutput)
        screenReader.timeRange = exportTimeRange

        let separatesRecording = configuration.deliveryOptions.separateAudioTracks && configuration.audioReplacementURL == nil
        var audioOutput: AVAssetReaderAudioMixOutput?
        var replacementReader: AVAssetReader?
        var clipSources: [RecordingAudioClipSource] = []
        if !configuration.exportSettings.removeAudio {
            if let directory = configuration.mediaDirectory {
                for clip in configuration.audioClips {
                    if let source = await RecordingAudioClipSource.load(clip, in: directory) {
                        clipSources.append(source)
                    }
                }
            }
            let mixed: (reader: AVAssetReader, output: AVAssetReaderAudioMixOutput)? = clipSources.isEmpty
                ? nil
                : try await Self.makeMixedAudio(
                    recordingTracks: separatesRecording ? [] : audioTracks,
                    replacementURL: configuration.audioReplacementURL,
                    clips: clipSources,
                    timeRange: exportTimeRange,
                    volume: configuration.audioVolume,
                    clipTimeline: clipTimeline,
                    monoAudio: configuration.deliveryOptions.monoAudio
                )
            if let mixed {
                replacementReader = mixed.reader
                audioOutput = mixed.output
            } else if let replacementURL = configuration.audioReplacementURL {
                let replacementAsset = AVURLAsset(url: replacementURL)
                let replacementTracks = try await replacementAsset.loadTracks(withMediaType: .audio)
                if !replacementTracks.isEmpty {
                    let reader = try AVAssetReader(asset: replacementAsset)
                    reader.timeRange = exportTimeRange
                    let output = AVAssetReaderAudioMixOutput(
                        audioTracks: replacementTracks,
                        audioSettings: RecordingAudioChannels.decodedSettings(mono: configuration.deliveryOptions.monoAudio)
                    )
                    output.audioMix = RecordingAudioGain.makeMix(tracks: replacementTracks, volume: configuration.audioVolume)
                    output.alwaysCopiesSampleData = false
                    reader.add(output)
                    replacementReader = reader
                    audioOutput = output
                }
            } else if !audioTracks.isEmpty && !separatesRecording {
                let output = AVAssetReaderAudioMixOutput(
                    audioTracks: audioTracks,
                    audioSettings: RecordingAudioChannels.decodedSettings(mono: configuration.deliveryOptions.monoAudio)
                )
                output.audioMix = RecordingAudioGain.makeMix(
                    tracks: audioTracks, volume: configuration.audioVolume, clipTimeline: clipTimeline
                )
                output.alwaysCopiesSampleData = false
                screenReader.add(output)
                audioOutput = output
            }
        }

        let cameraFeed = try await CameraFrameFeed(
            url: configuration.cameraURL,
            offset: configuration.cameraOffset,
            loopingTo: configuration.cameraLoops ? sourceDuration : nil,
            beauty: StudioCameraBeautyFrameFilter(beauty: configuration.style.camera.beauty)
        )

        let container = configuration.exportSettings.effectiveContainer
        let outputURL = Self.temporaryOutputURL(container: container)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: container.fileType)
        writer.shouldOptimizeForNetworkUse = container.supportsFastStart && configuration.growingUploadSource == nil

        let codec: AVVideoCodecType = configuration.exportSettings.codec == .hevc ? .hevc : .h264
        let bitrate = Self.averageBitRate(
            width: canvasWidth,
            height: canvasHeight,
            quality: configuration.exportSettings.quality,
            frameRate: timing.framesPerSecond,
            encodingMode: configuration.exportSettings.encodingMode
        )
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoExpectedSourceFrameRateKey: timing.framesPerSecond
        ]
        if let mode = configuration.exportSettings.encodingMode {
            compressionProperties[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = mode == .fast
        } else if codec == .hevc {
            compressionProperties[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true
        }
        AppLog.event("recording", "export_encoding_configured", fields: [
            "mode": configuration.exportSettings.encodingMode?.rawValue ?? "legacy",
            "codec": configuration.exportSettings.codec.rawValue,
            "bitrate": String(bitrate),
            "fps": String(timing.framesPerSecond), "width": String(canvasWidth), "height": String(canvasHeight)
        ])
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: canvasWidth,
            AVVideoHeightKey: canvasHeight,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: canvasWidth,
                kCVPixelBufferHeightKey as String: canvasHeight,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: configuration.deliveryOptions.monoAudio ? 1 : 2,
                AVEncoderBitRateKey: configuration.exportSettings.encodingMode == nil
                    ? 192_000 : configuration.exportSettings.quality.audioBitsPerSecond
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        let separatedAudio: [RecordingAudioTrackExport]
        if separatesRecording && !configuration.exportSettings.removeAudio {
            separatedAudio = try audioTracks.enumerated().map { index, track in
                let title = configuration.recordedAudioTrackNames.indices.contains(index)
                    ? configuration.recordedAudioTrackNames[index] : "Audio \(index + 1)"
                return try RecordingAudioTrackExport(
                    asset: screenAsset, track: track, timeRange: exportTimeRange,
                    volume: configuration.audioVolume, mono: configuration.deliveryOptions.monoAudio,
                    title: title, writer: writer, clipTimeline: clipTimeline
                )
            }
        } else {
            separatedAudio = []
        }
        defer { for stream in separatedAudio { stream.reader.cancelReading() } }
        for stream in separatedAudio {
            guard stream.reader.startReading() else { throw stream.reader.error ?? ExportError.writerFailed(nil) }
        }
        guard screenReader.startReading() else {
            throw screenReader.error ?? ExportError.writerFailed(nil)
        }
        if let replacementReader, !replacementReader.startReading() {
            screenReader.cancelReading()
            throw replacementReader.error ?? ExportError.writerFailed(nil)
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error)
        }
        writer.startSession(atSourceTime: exportStartTime)
        configuration.growingUploadSource?.opened(outputURL)

        let compositor = StudioFrameCompositor(
            canvasSize: canvasSize,
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
            includeBubble: cameraFeed != nil,
            cameraAspect: configuration.cameraAspect ?? RecordingCameraLayoutResolver.defaultCameraAspect,
            timing: timing,
            reframe: configuration.reframe,
            fitContentAspect: configuration.fitContentAspect,
            usesUniformPadding: configuration.usesUniformPadding,
            motionTimeline: configuration.motionTimeline,
            textOverlays: configuration.textOverlays,
            arrowOverlays: configuration.arrowOverlays,
            imageOverlays: configuration.imageOverlays,
            mediaDirectory: configuration.mediaDirectory
        )

        compositor.wallpaperVideo = wallpaperVideo

        var cutoutMattes: StudioCameraMatteTrack?
        if cameraFeed != nil, !configuration.cameraLoops, configuration.cameraLayoutTimeline.usesCutout, let cameraURL = configuration.cameraURL {
            let frameCount = timing.frameCount(for: clipTimeline.duration)
            let neededTimes = (0..<frameCount).compactMap { frame -> TimeInterval? in
                let editorTime = timing.time(forFrame: frame)
                guard compositor.showsCutout(at: editorTime) else { return nil }
                return clipTimeline.location(at: editorTime)?.sourceTime
            }
            if !neededTimes.isEmpty {
                cutoutMattes = await StudioCameraMatteTrack(
                    url: cameraURL, offset: configuration.cameraOffset, neededTimes: neededTimes
                )
                compositor.cutoutMattes = cutoutMattes
            }
        }

        let screenAudioOutput = audioOutput
        let writerAudioInput = audioInput

        do {
            async let videoDone: Void = pumpVideo(
                output: videoOutput,
                input: videoInput,
                adaptor: adaptor,
                compositor: compositor,
                cameraFeed: cameraFeed,
                redactionFilter: RecordingRedactionFrameFilter(redactions: configuration.redactions),
                clipTimeline: clipTimeline,
                timing: timing,
                cancelFlag: cancelFlag,
                progress: progress
            )
            async let audioDone: Void = pumpAudio(
                output: screenAudioOutput,
                input: writerAudioInput,
                cancelFlag: cancelFlag
            )
            async let separateDone: Void = Self.pumpSeparateAudio(separatedAudio, cancelFlag: cancelFlag)
            _ = try await (videoDone, audioDone, separateDone)
            if screenReader.status == .failed { throw screenReader.error ?? ExportError.writerFailed(nil) }
            if replacementReader?.status == .failed { throw replacementReader?.error ?? ExportError.writerFailed(nil) }
        } catch {
            screenReader.cancelReading()
            replacementReader?.cancelReading()
            cameraFeed?.cancel()
            cutoutMattes?.cancel()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        cameraFeed?.cancel()
        cutoutMattes?.cancel()
        withExtendedLifetime(clipSources) {}

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.writerFailed(writer.error)
        }
        AppLog.event("recording", "recording_audio_export", fields: ["included": String(describing: String(!configuration.exportSettings.removeAudio)), "mono": String(describing: String(configuration.deliveryOptions.monoAudio)), "separateTracks": String(describing: String(configuration.deliveryOptions.separateAudioTracks))])
        progress(1)
        return outputURL
    }

    private func pumpVideo(
        output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        compositor: StudioFrameCompositor,
        cameraFeed: CameraFrameFeed?,
        redactionFilter: RecordingRedactionFrameFilter?,
        clipTimeline: RecordingClipTimeline,
        timing: RecordingExportTiming,
        cancelFlag: CancelFlag,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let duration = clipTimeline.duration
        let frameCount = timing.frameCount(for: duration)

        var decodeSeconds = 0.0
        func nextSourceFrame() -> (buffer: CVPixelBuffer, time: TimeInterval)? {
            let decodeStart = CFAbsoluteTimeGetCurrent()
            defer { decodeSeconds += CFAbsoluteTimeGetCurrent() - decodeStart }
            while let sampleBuffer = output.copyNextSampleBuffer() {
                guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                return (buffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
            }
            return nil
        }

        var currentBuffer: CVPixelBuffer?
        var pending = nextSourceFrame()
        var previousClipID: UUID?
        var renderSeconds = 0.0
        var writerWaitSeconds = 0.0
        var cameraSeconds = 0.0
        var renderedFrames = 0
        defer {
            AppLog.event("recording", "export_frames_completed", fields: ["frames": String(describing: renderedFrames), "fps": String(describing: timing.framesPerSecond), "motion_blur": String(describing: timing.motionBlurLevel.rawValue), "metal_frames": String(describing: compositor.metalFrameCount), "reused_screen_frames": String(describing: compositor.reusedScreenFrameCount), "reused_composed_frames": String(describing: compositor.reusedComposedFrameCount), "render_seconds": String(describing: renderSeconds), "metal_seconds": String(describing: compositor.metalSeconds), "cutout_wait_seconds": String(describing: compositor.cutoutWaitSeconds), "decode_seconds": String(describing: decodeSeconds), "camera_seconds": String(describing: cameraSeconds), "writer_wait_seconds": String(describing: writerWaitSeconds)])
        }

        var cachedPool: CVPixelBufferPool?

        var inFlight: (frame: StudioFrameCompositor.PendingFrame, index: Int)?
        func finishAndAppend(_ begun: StudioFrameCompositor.PendingFrame, at index: Int) async throws {
            let renderStart = CFAbsoluteTimeGetCurrent()
            try autoreleasepool {
                try compositor.finish(begun)
            }
            renderSeconds += CFAbsoluteTimeGetCurrent() - renderStart
            renderedFrames += 1

            let waitStart = CFAbsoluteTimeGetCurrent()
            while !input.isReadyForMoreMediaData {
                if cancelFlag.isCancelled { throw ExportError.cancelled }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            writerWaitSeconds += CFAbsoluteTimeGetCurrent() - waitStart

            if !adaptor.append(begun.destination, withPresentationTime: timing.presentationTime(forFrame: index)) {
                throw ExportError.writerFailed(nil)
            }
            if index % 10 == 0 {
                progress(min(0.98, Double(index) / Double(frameCount)))
            }
        }

        for frame in 0..<frameCount {
            if cancelFlag.isCancelled { throw ExportError.cancelled }
            let editorTime = timing.time(forFrame: frame)
            guard let location = clipTimeline.location(at: editorTime) else { break }
            let sourceTime = location.sourceTime

            if previousClipID != location.segmentID {
                if previousClipID != nil {
                    currentBuffer = nil
                }
                previousClipID = location.segmentID
            }

            while let sample = pending, sample.time <= editorTime {
                currentBuffer = sample.buffer
                pending = nextSourceFrame()
            }
            guard let decodedBuffer = currentBuffer ?? pending?.buffer else { break }
            let sourceBuffer = redactionFilter?.apply(to: decodedBuffer, atSourceTime: sourceTime) ?? decodedBuffer

            if cachedPool == nil { cachedPool = adaptor.pixelBufferPool }
            guard let pool = cachedPool else {
                throw ExportError.writerFailed(nil)
            }
            let cameraStart = CFAbsoluteTimeGetCurrent()
            let camera = cameraFeed?.latestFrame(at: sourceTime)
            cameraSeconds += CFAbsoluteTimeGetCurrent() - cameraStart
            let nextTime = timing.time(forFrame: frame + 1)
            let sourceRepeats = (pending == nil || pending!.time > nextTime)
                && clipTimeline.location(at: nextTime)?.segmentID == location.segmentID
            let renderStart = CFAbsoluteTimeGetCurrent()
            let begun = try autoreleasepool {
                try compositor.begin(
                    screenFrame: sourceBuffer,
                    cameraFrame: camera?.buffer,
                    cameraTime: camera?.time ?? 0,
                    editorTime: editorTime,
                    sourceTime: sourceTime,
                    sourceRepeatsOnNextFrame: sourceRepeats,
                    pool: pool
                )
            }
            renderSeconds += CFAbsoluteTimeGetCurrent() - renderStart

            if let previous = inFlight {
                try await finishAndAppend(previous.frame, at: previous.index)
            }
            inFlight = (begun, frame)
        }
        if let previous = inFlight {
            try await finishAndAppend(previous.frame, at: previous.index)
        }
        input.markAsFinished()
    }

    private static func makeMixedAudio(
        recordingTracks: [AVAssetTrack],
        replacementURL: URL?,
        clips: [RecordingAudioClipSource],
        timeRange: CMTimeRange,
        volume: Double,
        clipTimeline: RecordingClipTimeline,
        monoAudio: Bool = false
    ) async throws -> (reader: AVAssetReader, output: AVAssetReaderAudioMixOutput)? {
        let composition = AVMutableComposition()
        var recordingTrackIDs: [CMPersistentTrackID] = []
        if let replacementURL {
            let replacement = AVURLAsset(url: replacementURL)
            if let track = try await replacement.loadTracks(withMediaType: .audio).first {
                let length = min(try await replacement.load(.duration), timeRange.duration)
                if let added = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try added.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero)
                    recordingTrackIDs.append(added.trackID)
                }
            }
        } else {
            for track in recordingTracks {
                guard let added = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let available = try await track.load(.timeRange)
                let range = CMTimeRangeGetIntersection(timeRange, otherRange: available)
                guard range.duration > .zero else { continue }
                try added.insertTimeRange(range, of: track, at: range.start)
                recordingTrackIDs.append(added.trackID)
            }
        }
        let clipTrackIDs = RecordingAudioClipMixer.insert(clips, into: composition, videoDuration: timeRange.duration.seconds)
        let tracks = composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = timeRange
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: RecordingAudioChannels.decodedSettings(mono: monoAudio))
        output.audioMix = RecordingAudioClipMixer.mix(
            recordingTracks: tracks.filter { recordingTrackIDs.contains($0.trackID) },
            recordingVolume: volume,
            clips: clips.map(\.clip),
            trackIDs: clipTrackIDs,
            clipTimeline: replacementURL == nil ? clipTimeline : nil
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        return (reader, output)
    }

    private static func pumpSeparateAudio(_ streams: [RecordingAudioTrackExport], cancelFlag: CancelFlag) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for stream in streams {
                group.addTask { try await stream.pump { cancelFlag.isCancelled } }
            }
            try await group.waitForAll()
        }
    }

    private func pumpAudio(
        output: AVAssetReaderAudioMixOutput?,
        input: AVAssetWriterInput?,
        cancelFlag: CancelFlag
    ) async throws {
        guard let output, let input else { return }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if cancelFlag.isCancelled { throw ExportError.cancelled }
            while !input.isReadyForMoreMediaData {
                if cancelFlag.isCancelled { throw ExportError.cancelled }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            if !input.append(sampleBuffer) {
                throw ExportError.writerFailed(nil)
            }
        }
        input.markAsFinished()
    }

    private static func temporaryOutputURL(container: VideoExportContainer) -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Upshot", isDirectory: true)
            .appendingPathComponent("StudioExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(UUID().uuidString).\(container.fileExtension)")
    }

    private static func outputSize(
        source: CGSize,
        settings: VideoCompressionSettings
    ) throws -> CGSize {
        if settings.resolution == .custom {
            guard settings.hasValidCustomResolution else {
                AppLog.event("recording", "export_resolution_invalid", fields: [
                    "width": String(settings.effectiveCustomWidth), "height": String(settings.effectiveCustomHeight)
                ])
                throw ExportError.invalidResolution
            }
            return CGSize(width: settings.effectiveCustomWidth, height: settings.effectiveCustomHeight)
        }
        guard source.width.isFinite, source.height.isFinite, source.width > 0, source.height > 0 else {
            return CGSize(width: 1920, height: 1080)
        }
        if settings.resolutionUsesLongestEdge == true || [.p1440, .p2160].contains(settings.resolution) {
            guard let edge = settings.resolution.longestEdge else { return source }
            let scale = edge / max(source.width, source.height)
            return CGSize(
                width: max(2, Int((source.width * scale).rounded(.down)) & ~1),
                height: max(2, Int((source.height * scale).rounded(.down)) & ~1)
            )
        }
        let requestedHeight: CGFloat?
        switch settings.resolution {
        case .original: requestedHeight = nil
        case .custom, .p1440, .p2160: requestedHeight = nil
        case .p1080: requestedHeight = 1080
        case .p720: requestedHeight = 720
        case .p480: requestedHeight = 480
        }
        guard let requestedHeight, source.height > requestedHeight else { return source }
        return CGSize(
            width: source.width * requestedHeight / source.height,
            height: requestedHeight
        )
    }

    private static func averageBitRate(
        width: Int,
        height: Int,
        quality: VideoCompressionQuality,
        frameRate: Double,
        encodingMode: VideoExportEncodingMode?
    ) -> Int {
        if let encodingMode {
            let pixels = Double(width) * Double(height)
            let highQuality = quality == .high
            let hd = highQuality ? 8_000_000.0 : 5_000_000.0
            let fhd = highQuality ? 12_000_000.0 : 8_000_000.0
            let uhd = highQuality ? 45_000_000.0 : 35_000_000.0
            let base: Double
            if pixels <= 1280 * 720 {
                base = hd
            } else if pixels <= 1920 * 1080 {
                base = fhd
            } else {
                let fraction = min(1, (pixels - 1920 * 1080) / Double(3840 * 2160 - 1920 * 1080))
                base = (fhd + (uhd - fhd) * fraction).rounded()
            }
            let qualityMultiplier = quality == .low ? 1.25 / 2.1 : 1
            let requested = base * sqrt(max(1, frameRate / 30)) * encodingMode.bitrateMultiplier * qualityMultiplier
            let detail = encodingMode == .quality ? pixels * frameRate * 0.3 : 0
            return max(2_500_000, Int(max(requested, detail).rounded()))
        }
        let factor: Double
        switch quality {
        case .high: factor = 3.2
        case .medium: factor = 2.1
        case .low: factor = 1.25
        }
        return max(2_500_000, Int(Double(width * height) * factor))
    }
}


nonisolated private final class CameraFrameFeed: @unchecked Sendable {
    private let reader: AVAssetReader
    private let output: AVAssetReaderOutput
    private let offset: TimeInterval
    private let beauty: StudioCameraBeautyFrameFilter?
    private var currentFrame: (buffer: CVPixelBuffer, time: TimeInterval)?
    private var isCurrentTouchedUp = false
    private var ahead: [(buffer: CVPixelBuffer, time: TimeInterval)] = []
    private var isFinished = false

    init?(url: URL?, offset: TimeInterval, loopingTo: TimeInterval? = nil, beauty: StudioCameraBeautyFrameFilter? = nil) async throws {
        guard let url else { return nil }
        let asset = try await RecordingCameraAsset.load(url: url, loopingTo: loopingTo)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let transform = try await track.load(.preferredTransform)
        let output: AVAssetReaderOutput
        if transform != .identity {
            let composed = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: settings)
            composed.videoComposition = try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
            output = composed
        } else {
            output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        }
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? RecordingStudioExporter.ExportError.noVideoTrack
        }

        self.reader = reader
        self.output = output
        self.offset = offset
        self.beauty = beauty
    }

    func latestFrame(at screenTime: TimeInterval) -> (buffer: CVPixelBuffer, time: TimeInterval)? {
        while true {
            if let next = ahead.first {
                guard next.time <= screenTime || currentFrame == nil else { break }
                currentFrame = next
                isCurrentTouchedUp = false
                ahead.removeFirst()
            } else if !decodeNext() {
                break
            }
        }
        if let beauty, let frame = currentFrame, !isCurrentTouchedUp {
            currentFrame = (beauty.apply(to: frame.buffer, time: frame.time), frame.time)
            isCurrentTouchedUp = true
        }
        return currentFrame
    }

    private func decodeNext() -> Bool {
        guard !isFinished else { return false }
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            ahead.append((buffer, CMSampleBufferGetPresentationTimeStamp(sample).seconds + offset))
            return true
        }
        isFinished = true
        return false
    }

    func cancel() {
        reader.cancelReading()
    }
}

nonisolated private struct SettledLayout: Hashable, Sendable {
    let layout: RecordingCameraLayout
    let isShrunk: Bool
    var cameraWidth: CGFloat = 0
}


nonisolated final class StudioFrameCompositor: @unchecked Sendable {
    var wallpaperVideo: StudioWallpaperVideoFrameSource?
    fileprivate final class LayoutResources {
        let layout: RecordingStudioLayout
        let backdrop: CGImage?
        var metalRenderer: StudioMetalScreenRenderer?
        var bubbleShadow: (image: CGImage, rect: CGRect)??
        var cameraScaler: StudioCameraBubbleScaler??
        var bubbleContentSource: CVPixelBuffer?
        var bubbleContentImage: CGImage?
        var scheduledCameraSource: CVPixelBuffer?
        var scheduledCameraSubmission: StudioCameraBubbleScaler.Submission?

        init(layout: RecordingStudioLayout, backdrop: CGImage?) {
            self.layout = layout
            self.backdrop = backdrop
        }
    }

    private let canvasSize: CGSize
    private let videoCropRect: CGRect
    private let style: RecordingStudioStyle
    private let baseLayout: RecordingStudioLayout
    private let layoutResolver: RecordingCameraLayoutResolver
    private let layoutTimeline: RecordingCameraLayoutTimeline
    private var layout: RecordingStudioLayout
    private var layoutResources: [(key: SettledLayout, resources: LayoutResources)] = []
    private static let maxLayoutResources = 2
    private var morphRenderer: StudioMetalScreenRenderer?
    private var morphRendererFailed = false
    private var didLogScreenMotionBlurFallback = false
    private var morphCameraRenderer: StudioMorphCameraRenderer?
    private var morphCameraRendererFailed = false
    var cutoutMattes: StudioCameraMatteTrack?
    private var fallbackMattesStorage: StudioCameraMatteGenerator??
    private var fallbackMattes: StudioCameraMatteGenerator? {
        if let storage = fallbackMattesStorage { return storage }
        let generator = StudioCameraMatteGenerator()
        fallbackMattesStorage = .some(generator)
        return generator
    }
    private(set) var cutoutWaitSeconds = 0.0
    private var morphShadowContextStorage: CGContext??
    private var morphShadowContext: CGContext? {
        if let storage = morphShadowContextStorage { return storage }
        let width = max(1, Int((canvasSize.width / Self.morphShadowScale).rounded(.up)))
        let height = max(1, Int((canvasSize.height / Self.morphShadowScale).rounded(.up)))
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        morphShadowContextStorage = .some(context)
        return context
    }
    private static let morphShadowScale: CGFloat = 4
    private var overlayOpacity: CGFloat = 1
    private let viewportTimeline: ViewportTimeline
    private let pointerTimeline: PointerTimeline?
    private let showsPressEffects: Bool
    private let clickEffectSettings: RecordingClickEffectSettings
    private let keystrokeTimeline: KeystrokeCaptionTimeline?
    private let keystrokePlacement: RecordingKeystrokePlacement
    private let keystrokeAppearance: RecordingKeystrokeAppearance
    private let shot: RecordingExportShot
    private let shotRenderer = RecordingExportShotRenderer()
    private let speedBadgeTimeline: SpeedBadgeTimeline?
    private let speedBadgePlacement: RecordingKeystrokePlacement
    private let subtitleTimeline: SubtitleTimeline?
    private let subtitleStyle: SubtitleBarStyle
    private let captionTimeline: StudioCaptionTimeline?
    private let captionCanvasSize: CGSize
    private let karaokeTimeline: KaraokeTimeline?
    private let reframe: ReframeTrack?
    private let motionTimeline: RecordingStudioMotionTimeline
    private let textOverlays: [RecordingTextOverlay]
    private let arrowOverlays: [RecordingArrowOverlay]
    private let imageOverlays: [RecordingImageOverlay]
    private let mediaDirectory: URL?
    private let overlayImages = RecordingOverlayImageStore()
    private var artworkImageCache: [String: CGImage] = [:]
    private var pointerMaterialRendererStorage: PointerMaterialRenderer?
    private var pointerMaterialRenderer: PointerMaterialRenderer {
        if let storage = pointerMaterialRendererStorage { return storage }
        let renderer = PointerMaterialRenderer()
        pointerMaterialRendererStorage = renderer
        return renderer
    }
    private let pointerScale: CGFloat
    private let colorSpace: CGColorSpace
    private let plainBackdrop: CGImage?
    private let timing: RecordingExportTiming
    private var metalFailed = false
    private(set) var metalFrameCount = 0
    private(set) var metalSeconds = 0.0
    private let screenLayerCache = StudioScreenLayerCache()
    private var plannedCacheKey: (source: CVPixelBuffer, rect: CGRect, layout: SettledLayout)?
    private(set) var reusedScreenFrameCount = 0
    private let composedFrameCache = StudioComposedFrameCache<ComposedFrameState>()
    private(set) var reusedComposedFrameCount = 0
    private let bypassFrameCache = ProcessInfo.processInfo.environment["UPSHOT_EXPORT_BYPASS_FRAME_CACHE"] == "1"
    private let bypassScreenCache = ProcessInfo.processInfo.environment["UPSHOT_EXPORT_BYPASS_SCREEN_CACHE"] == "1"
    private let forceCoreGraphics = ProcessInfo.processInfo.environment["UPSHOT_EXPORT_RENDERER"] == "cpu"

    init(
        canvasSize: CGSize,
        videoCropRect: CGRect,
        style: RecordingStudioStyle,
        cameraLayoutTimeline: RecordingCameraLayoutTimeline,
        viewportTimeline: ViewportTimeline,
        pointerTimeline: PointerTimeline?,
        showsPressEffects: Bool,
        clickEffectSettings: RecordingClickEffectSettings = RecordingClickEffectSettings(),
        keystrokeTimeline: KeystrokeCaptionTimeline?,
        keystrokePlacement: RecordingKeystrokePlacement,
        keystrokeAppearance: RecordingKeystrokeAppearance = RecordingKeystrokeAppearance(),
        shot: RecordingExportShot = .flat,
        speedBadgeTimeline: SpeedBadgeTimeline? = nil,
        speedBadgePlacement: RecordingKeystrokePlacement = .topRight,
        subtitleTimeline: SubtitleTimeline?,
        subtitleStyle: SubtitleBarStyle = SubtitleBarStyle(),
        captionTimeline: StudioCaptionTimeline? = nil,
        captionCanvasSize: CGSize? = nil,
        karaokeTimeline: KaraokeTimeline? = nil,
        includeBubble: Bool,
        cameraAspect: CGFloat = RecordingCameraLayoutResolver.defaultCameraAspect,
        timing: RecordingExportTiming,
        reframe: ReframeTrack? = nil,
        fitContentAspect: CGFloat? = nil,
        usesUniformPadding: Bool = false,
        motionTimeline: RecordingStudioMotionTimeline = .none,
        textOverlays: [RecordingTextOverlay] = [],
        arrowOverlays: [RecordingArrowOverlay] = [],
        imageOverlays: [RecordingImageOverlay] = [],
        mediaDirectory: URL? = nil
    ) {
        self.canvasSize = canvasSize
        self.textOverlays = textOverlays
        self.arrowOverlays = arrowOverlays
        self.imageOverlays = mediaDirectory == nil ? [] : imageOverlays
        self.mediaDirectory = mediaDirectory
        self.videoCropRect = RecordingVideoCropGeometry.normalized(videoCropRect)
        self.style = style
        let baseLayout = RecordingStudioLayout.make(
            canvasSize: canvasSize,
            style: style,
            usesUniformPadding: usesUniformPadding,
            contentAspect: reframe?.sourceAspect ?? fitContentAspect,
            contentMode: fitContentAspect != nil && reframe == nil ? .fit : .fill,
            contentCropRect: videoCropRect
        )
        self.baseLayout = baseLayout
        self.layoutResolver = RecordingCameraLayoutResolver(
            base: baseLayout,
            style: style,
            showsCamera: includeBubble,
            cameraAspect: cameraAspect
        )
        self.layoutTimeline = cameraLayoutTimeline
        self.layout = baseLayout
        self.viewportTimeline = viewportTimeline
        self.pointerTimeline = style.hidesCursor ? nil : pointerTimeline
        self.showsPressEffects = showsPressEffects
        self.clickEffectSettings = clickEffectSettings.normalized
        self.keystrokeTimeline = keystrokeTimeline
        self.keystrokePlacement = keystrokePlacement
        self.keystrokeAppearance = keystrokeAppearance
        self.shot = shot
        self.speedBadgeTimeline = speedBadgeTimeline
        self.speedBadgePlacement = speedBadgePlacement
        self.subtitleTimeline = subtitleTimeline
        self.subtitleStyle = subtitleStyle
        self.captionTimeline = captionTimeline
        self.captionCanvasSize = captionCanvasSize ?? canvasSize
        self.karaokeTimeline = karaokeTimeline
        self.reframe = reframe
        self.motionTimeline = motionTimeline
        self.timing = timing
        self.pointerScale = style.cursorScale
        self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.plainBackdrop = Self.renderBackdrop(
            canvasSize: canvasSize,
            layout: nil,
            style: style,
            colorSpace: colorSpace
        )
    }

    private func frameLayout(at editorTime: TimeInterval) -> (
        layout: RecordingStudioLayout,
        settled: SettledLayout?
    ) {
        if let frame = motionTimeline.layoutFrame(at: editorTime, canvasSize: canvasSize) {
            let layout = baseLayout.applying(frame)
            guard motionTimeline.isLayoutSettled(at: editorTime) else { return (layout, nil) }
            return (layout, SettledLayout(
                layout: layoutTimeline.layout(at: editorTime),
                isShrunk: motionTimeline.isZoomed(at: editorTime),
                cameraWidth: layout.bubbleRect.width
            ))
        }
        let state = layoutTimeline.state(at: editorTime)
        let zoomProgress = viewportTimeline.zoomProgress(at: editorTime)
        let layout = layoutResolver.layout(for: state, zoomProgress: zoomProgress,
                                           magnification: viewportFrame(at: editorTime).magnification)
        guard let settled = state.settledLayout else { return (layout, nil) }
        if settled.kind == .pictureInPicture, style.camera.zoomResponse == .magnification {
            guard zoomProgress < 0.0001 || zoomProgress > 0.9999 else { return (layout, nil) }
            return (layout, SettledLayout(layout: settled, isShrunk: zoomProgress > 0.5,
                                          cameraWidth: layout.bubbleRect.width))
        }
        guard settled.kind == .pictureInPicture || settled.kind == .cutout else {
            return (layout, SettledLayout(layout: settled, isShrunk: false))
        }
        let scale = layoutResolver.cameraScale(forZoomProgress: zoomProgress)
        if abs(scale - 1) < 0.0001 {
            return (layout, SettledLayout(layout: settled, isShrunk: false))
        }
        if abs(scale - layoutResolver.zoomedCameraScale) < 0.0001 {
            return (layout, SettledLayout(layout: settled, isShrunk: true))
        }
        return (layout, nil)
    }

    private func screenDrawRect(at editorTime: TimeInterval) -> CGRect {
        frameLayout(at: editorTime).layout.frameRect(for: viewportFrame(at: editorTime))
    }

    private func resources(for key: SettledLayout, layout: RecordingStudioLayout) -> LayoutResources {
        if let index = layoutResources.firstIndex(where: { $0.key == key }) {
            let entry = layoutResources.remove(at: index)
            layoutResources.append(entry)
            return entry.resources
        }
        let resources = LayoutResources(
            layout: layout,
            backdrop: Self.renderBackdrop(
                canvasSize: canvasSize,
                layout: layout.screenOpacity > 0.001 ? layout : nil,
                style: style,
                colorSpace: colorSpace
            )
        )
        layoutResources.append((key, resources))
        if layoutResources.count > Self.maxLayoutResources {
            layoutResources.removeFirst()
        }
        return resources
    }

    private func viewportFrame(at editorTime: TimeInterval) -> ViewportFrame {
        if let viewport = motionTimeline.viewport(at: editorTime) { return viewport }
        let base = reframe?.frame(at: editorTime) ?? viewportTimeline.frame(at: editorTime)
        return RecordingVideoCropGeometry.viewport(base, crop: videoCropRect)
    }

    private struct ComposedFrameState: Equatable {
        let screen: CVPixelBuffer?
        let camera: CVPixelBuffer?
        let layout: RecordingStudioLayout
        let screenRect: CGRect?
        let pointer: PointerFrame?
        let keystroke: KeystrokeCaptionFrame?
        let speedBadge: SpeedBadgeFrame?
        let subtitle: String?
        let karaoke: KaraokeTimeline.Line?

        static func == (a: Self, b: Self) -> Bool {
            a.screen === b.screen && a.camera === b.camera && a.layout == b.layout
                && a.screenRect == b.screenRect && a.pointer == b.pointer
                && a.keystroke == b.keystroke && a.speedBadge == b.speedBadge
                && a.subtitle == b.subtitle && a.karaoke == b.karaoke
        }
    }

    private func composedState(
        screenFrame: CVPixelBuffer, cameraFrame: CVPixelBuffer?,
        layout: RecordingStudioLayout, settled: SettledLayout?, sampleRects: [CGRect],
        editorTime: TimeInterval, sourceTime: TimeInterval
    ) -> ComposedFrameState? {
        guard wallpaperVideo == nil else { return nil }
        guard shot != .orbit, !bypassFrameCache, settled != nil, sampleRects.count <= 1 else { return nil }
        if subtitleStyle.preset != .upshot, captionTimeline?.cue(at: sourceTime) != nil { return nil }
        guard !arrowOverlays.contains(where: { $0.isActive(atSourceTime: sourceTime) }), !textOverlays.contains(where: { $0.isActive(atSourceTime: sourceTime) }),
              !imageOverlays.contains(where: { $0.isActive(atSourceTime: sourceTime) }) else { return nil }
        let showsScreen = layout.screenOpacity > 0.001
        let showsCamera = layout.cameraOpacity > 0.001 && layout.bubbleRect.width > 0
        let subtitle = subtitleTimeline?.text(at: sourceTime)
        return ComposedFrameState(
            screen: showsScreen ? screenFrame : nil,
            camera: showsCamera ? cameraFrame : nil,
            layout: layout,
            screenRect: sampleRects.first,
            pointer: showsScreen ? pointerTimeline?.frame(at: editorTime) : nil,
            keystroke: showsScreen ? keystrokeTimeline?.frame(at: sourceTime) : nil,
            speedBadge: showsScreen ? speedBadgeTimeline?.frame(at: editorTime) : nil,
            subtitle: subtitle,
            karaoke: subtitle != nil && subtitleStyle.highlightsSpokenWord ? karaokeTimeline?.line(at: sourceTime) : nil
        )
    }

    struct PendingFrame {
        fileprivate let screenFrame: CVPixelBuffer
        fileprivate let cameraFrame: CVPixelBuffer?
        fileprivate let cameraTime: TimeInterval
        fileprivate let editorTime: TimeInterval
        fileprivate let sourceTime: TimeInterval
        fileprivate let layout: RecordingStudioLayout
        fileprivate let settledLayout: SettledLayout?
        fileprivate let sampleRects: [CGRect]
        fileprivate let screenMotionBlur: StudioScreenMotionBlur
        fileprivate let shouldCacheScreen: Bool
        fileprivate let plansRestore: Bool
        fileprivate let submission: StudioMetalScreenRenderer.Submission?
        fileprivate let resources: LayoutResources?
        fileprivate let cameraSubmission: StudioCameraBubbleScaler.Submission?
        fileprivate let reusesComposedFrame: Bool
        let destination: CVPixelBuffer
    }

    func begin(
        screenFrame: CVPixelBuffer,
        cameraFrame: CVPixelBuffer?,
        cameraTime: TimeInterval = 0,
        editorTime: TimeInterval,
        sourceTime: TimeInterval,
        sourceRepeatsOnNextFrame: Bool,
        pool: CVPixelBufferPool
    ) throws -> PendingFrame {
        let (frameLayout, settled) = frameLayout(at: editorTime)
        let showsScreen = frameLayout.screenOpacity > 0.001
        let sampleRects = showsScreen
            ? timing.screenSampleRects(at: editorTime, frameRect: screenDrawRect(at:))
            : []
        let sampleCount = sampleRects.count
        let screenMotionBlur = showsScreen ? timing.screenMotionBlur(
            at: editorTime, stageSize: canvasSize, frameRect: screenDrawRect(at:)
        ) : StudioScreenMotionBlur()
        let composedState = screenMotionBlur.isActive ? nil : composedState(
            screenFrame: screenFrame, cameraFrame: cameraFrame,
            layout: frameLayout, settled: settled, sampleRects: sampleRects,
            editorTime: editorTime, sourceTime: sourceTime
        )
        if let composedState, let cached = composedFrameCache.frame(matching: composedState) {
            return PendingFrame(
                screenFrame: screenFrame, cameraFrame: cameraFrame, cameraTime: cameraTime,
                editorTime: editorTime, sourceTime: sourceTime, layout: frameLayout,
                settledLayout: settled, sampleRects: sampleRects, screenMotionBlur: screenMotionBlur, shouldCacheScreen: false,
                plansRestore: false, submission: nil, resources: nil, cameraSubmission: nil,
                reusesComposedFrame: true, destination: cached
            )
        }
        var destinationBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destinationBuffer) == kCVReturnSuccess,
              let destination = destinationBuffer else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }
        let plansRestore = wallpaperVideo == nil && !screenMotionBlur.isActive && !bypassScreenCache && sampleCount == 1
            && plannedCacheKey.map {
                $0.source === screenFrame && $0.rect == sampleRects[0] && $0.layout == settled
            } == true
        let shouldCacheScreen = wallpaperVideo == nil && !screenMotionBlur.isActive && !bypassScreenCache && sourceRepeatsOnNextFrame && sampleCount == 1
            && settled != nil
            && self.frameLayout(at: editorTime + timing.frameInterval).settled == settled
            && sampleRects[0] == screenDrawRect(at: editorTime + timing.frameInterval)
            && StudioScreenLayerCache.canCapture(width: Int(canvasSize.width), height: Int(canvasSize.height))
        if !shouldCacheScreen {
            plannedCacheKey = nil
        } else if !plansRestore, let settled {
            plannedCacheKey = (screenFrame, sampleRects[0], settled)
        }

        let submission: StudioMetalScreenRenderer.Submission? = if plansRestore {
            nil
        } else if settled == nil {
            submitMorphMetal(
                screenFrame: screenFrame, sampleRects: sampleRects, layout: frameLayout,
                motionBlur: screenMotionBlur, into: destination
            )
        } else {
            submitMetal(
                screenFrame: screenFrame, sampleRects: sampleRects, settled: settled,
                layout: frameLayout, motionBlur: screenMotionBlur, into: destination
            )
        }
        let resources = settled.map { resources(for: $0, layout: frameLayout) }
        let showsCamera = cameraFrame != nil && frameLayout.bubbleRect.width > 0 && frameLayout.cameraOpacity > 0.001
        let cameraSubmission = if let resources, let cameraFrame, showsCamera, frameLayout.cameraCutout <= 0.001 {
            prepareCamera(cameraFrame, resources: resources)
        } else {
            nil as StudioCameraBubbleScaler.Submission?
        }
        composedFrameCache.store(destination, state: composedState)
        return PendingFrame(
            screenFrame: screenFrame,
            cameraFrame: cameraFrame,
            cameraTime: cameraTime,
            editorTime: editorTime,
            sourceTime: sourceTime,
            layout: frameLayout,
            settledLayout: settled,
            sampleRects: sampleRects,
            screenMotionBlur: screenMotionBlur,
            shouldCacheScreen: shouldCacheScreen,
            plansRestore: plansRestore,
            submission: submission,
            resources: resources,
            cameraSubmission: cameraSubmission,
            reusesComposedFrame: false,
            destination: destination
        )
    }

    func finish(_ frame: PendingFrame) throws {
        if frame.reusesComposedFrame {
            reusedComposedFrameCount += 1
            return
        }
        layout = frame.layout
        let destination = frame.destination
        let screenFrame = frame.screenFrame
        let sampleRects = frame.sampleRects
        let settled = frame.settledLayout
        let resources = frame.resources
        let reusedScreen = frame.plansRestore && screenLayerCache.restore(
            source: screenFrame, rect: sampleRects[0], into: destination
        )
        if reusedScreen { reusedScreenFrameCount += 1 }
        else { screenLayerCache.invalidate() }

        var renderedWithMetal = false
        if !reusedScreen,
           let submission = frame.submission ?? submitMetal(
               screenFrame: screenFrame, sampleRects: sampleRects, settled: settled,
               layout: frame.layout, motionBlur: frame.screenMotionBlur, into: destination
           ) {
            let waitStart = CFAbsoluteTimeGetCurrent()
            renderedWithMetal = StudioMetalScreenRenderer.wait(for: submission)
            metalSeconds += CFAbsoluteTimeGetCurrent() - waitStart
            if renderedWithMetal { metalFrameCount += 1 }
            else { metalFailed = true }
        }
        let shouldCacheScreen = frame.shouldCacheScreen
        if frame.screenMotionBlur.isActive, !reusedScreen, !renderedWithMetal, !didLogScreenMotionBlurFallback {
            didLogScreenMotionBlurFallback = true
            let reason = forceCoreGraphics ? "requested_cpu" : (wallpaperVideo == nil ? "metal_unavailable" : "wallpaper_video")
            AppLog.event("rendering", reason == "metal_unavailable" ? "screen_motion_blur_metal_failed" : "screen_motion_blur_fallback", fields: [
                "fallback": "core_graphics", "reason": reason, "mode": String(describing: frame.screenMotionBlur.mode)
            ])
        }
        let editorTime = frame.editorTime
        let sourceTime = frame.sourceTime
        let cameraFrame = frame.cameraFrame
        CVPixelBufferLockBaseAddress(destination, [])
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        guard var context = lockedContext(for: destination) else {
            throw RecordingStudioExporter.ExportError.writerFailed(nil)
        }

        var wallpaperBackdrop: CGImage?
        let screenOpacity = layout.screenOpacity
        if !reusedScreen, !renderedWithMetal {
            if let wallpaperVideo {
                let wallpaperFrame = try wallpaperVideo.image(at: editorTime)
                wallpaperBackdrop = Self.renderBackdrop(
                    canvasSize: canvasSize, layout: nil, style: style,
                    colorSpace: colorSpace, wallpaperFrame: wallpaperFrame
                )
                drawBackdrop(wallpaperBackdrop, in: context)
                drawCardShadow(for: layout, in: context)
            } else if let resources {
                drawBackdrop(resources.backdrop, in: context)
            } else {
                drawBackdrop(plainBackdrop, in: context)
                drawCardShadow(for: layout, in: context)
            }
        }

        var renderedScreen = reusedScreen || renderedWithMetal
        if !reusedScreen, !renderedWithMetal, !sampleRects.isEmpty,
           let screenImage = Self.makeImage(from: screenFrame, colorSpace: colorSpace) {
            if settled != nil {
                context.saveGState()
                context.addPath(roundedPath(for: layout.cardRect, radius: layout.cardCornerRadius))
                context.clip()
                for (sample, drawRect) in sampleRects.enumerated() {
                    context.setAlpha(1 / CGFloat(sample + 1))
                    frame.screenMotionBlur.draw(screenImage, in: drawRect, canvasHeight: canvasSize.height, context: context)
                }
                context.restoreGState()
            } else {
                drawMorphingScreen(
                    screenImage, editorTime: editorTime, opacity: screenOpacity,
                    motionBlur: frame.screenMotionBlur, in: context
                )
            }
            renderedScreen = true
        }

        if shouldCacheScreen, !reusedScreen, renderedScreen {
            context.flush()
            screenLayerCache.capture(source: screenFrame, rect: sampleRects[0], fromLocked: destination)
        }
        if !shouldCacheScreen { screenLayerCache.invalidate() }

        overlayOpacity = screenOpacity
        if screenOpacity > 0.001 {
            drawPointer(editorTime: editorTime, in: context)

            drawKeystrokeCaption(at: sourceTime, in: context)

            drawSpeedBadge(at: editorTime, in: context)
        }

        if screenOpacity > 0.001, shot != .flat {
            try shotRenderer.draw(
                shot: shot, card: layout.cardRect, cornerRadius: layout.cardCornerRadius,
                canvasSize: canvasSize, background: wallpaperBackdrop ?? plainBackdrop, shadow: style.shadow,
                shadowLayers: style.usesLayeredShadow ? style.shadowLayers(canvasSize: canvasSize) : nil,
                time: editorTime, in: context
            )
        }

        if let cameraFrame, layout.bubbleRect.width > 0, layout.cameraOpacity > 0.001 {

            if layout.cameraCutout > 0.001 {
                context.flush()
                CVPixelBufferUnlockBaseAddress(destination, [])
                let drawn = renderCutoutCamera(
                    cameraFrame, cameraTime: frame.cameraTime, editorTime: editorTime, into: destination
                )
                CVPixelBufferLockBaseAddress(destination, [])
                guard let relocked = lockedContext(for: destination) else {
                    throw RecordingStudioExporter.ExportError.writerFailed(nil)
                }
                context = relocked
                if !drawn {
                    drawMorphingCamera(cameraFrame, editorTime: editorTime, in: context)
                }
            } else if let resources {
                drawCameraBubble(cameraFrame, resources: resources, submission: frame.cameraSubmission, in: context)
            } else {
                context.flush()
                CVPixelBufferUnlockBaseAddress(destination, [])
                let drawn = renderMorphingCamera(cameraFrame, editorTime: editorTime, into: destination)
                CVPixelBufferLockBaseAddress(destination, [])
                guard let relocked = lockedContext(for: destination) else {
                    throw RecordingStudioExporter.ExportError.writerFailed(nil)
                }
                context = relocked
                if !drawn {
                    drawMorphingCamera(cameraFrame, editorTime: editorTime, in: context)
                }
            }
        }

        let placement = RecordingOverlayPlacement(layout: layout, viewport: viewportFrame(at: editorTime))
        drawArrowOverlays(at: sourceTime, placement: placement, in: context)
        drawImageOverlays(at: sourceTime, placement: placement, in: context)
        drawTextOverlays(at: sourceTime, placement: placement, in: context)

        drawSubtitleBar(at: sourceTime, in: context)
    }

    private func drawArrowOverlays(at sourceTime: TimeInterval, placement: RecordingOverlayPlacement, in context: CGContext) {
        let active = arrowOverlays.filter { $0.isActive(atSourceTime: sourceTime) }
        guard !active.isEmpty else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: 0, y: canvasSize.height)
        context.scaleBy(x: 1, y: -1)
        for overlay in active {
            placement.draw(space: overlay.coordinateSpace, canvasSize: canvasSize, in: context) { size in
                RecordingArrowOverlayRenderer.draw(overlay, canvasSize: size, in: context)
            }
        }
    }

    private func drawImageOverlays(at sourceTime: TimeInterval, placement: RecordingOverlayPlacement, in context: CGContext) {
        guard let mediaDirectory else { return }
        let active = imageOverlays.filter { $0.isActive(atSourceTime: sourceTime) }
        guard !active.isEmpty else { return }
        context.saveGState()
        context.translateBy(x: 0, y: canvasSize.height)
        context.scaleBy(x: 1, y: -1)
        for overlay in active {
            guard let image = overlayImages.image(at: mediaDirectory.appendingPathComponent(overlay.fileName)) else { continue }
            RecordingImageOverlayRenderer.draw(overlay, image: image, atSourceTime: sourceTime, canvasSize: canvasSize, placement: placement, in: context)
        }
        context.restoreGState()
    }

    private func drawTextOverlays(at sourceTime: TimeInterval, placement: RecordingOverlayPlacement, in context: CGContext) {
        let active = textOverlays.filter { $0.isActive(atSourceTime: sourceTime) }
        guard !active.isEmpty else { return }
        context.saveGState()
        context.translateBy(x: 0, y: canvasSize.height)
        context.scaleBy(x: 1, y: -1)
        for overlay in active {
            RecordingTextOverlayRenderer.draw(overlay, atSourceTime: sourceTime, canvasSize: canvasSize, placement: placement, in: context)
        }
        context.restoreGState()
    }

    nonisolated static func castShadow(
        of path: CGPath,
        in context: CGContext,
        offset: CGSize,
        blur: CGFloat,
        color: CGColor,
        baseUnitsPerPoint: CGFloat = 1
    ) {
        let visible = context.boundingBoxOfClipPath
        let shape = path.boundingBoxOfPath
        guard !shape.isNull, !visible.isNull else { return }
        let shift = (shape.maxX - visible.minX + 2).rounded(.up)
        context.saveGState()
        context.translateBy(x: -shift, y: 0)
        context.setShadow(
            offset: CGSize(width: offset.width + shift * baseUnitsPerPoint, height: offset.height),
            blur: blur,
            color: color
        )
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }

    private func drawBackdrop(_ backdrop: CGImage?, in context: CGContext) {
        if let backdrop {
            context.draw(backdrop, in: CGRect(origin: .zero, size: canvasSize))
        } else {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(origin: .zero, size: canvasSize))
        }
    }

    private func drawCardShadow(for layout: RecordingStudioLayout, in context: CGContext) {
        let opacity = layout.screenOpacity
        guard opacity > 0.001, style.shadow > 0, style.background != .none,
              let shadowContext = morphShadowContext else { return }
        let scale = Self.morphShadowScale
        let small = CGRect(x: 0, y: 0, width: shadowContext.width, height: shadowContext.height)
        shadowContext.clear(small)
        shadowContext.saveGState()
        shadowContext.scaleBy(x: 1 / scale, y: 1 / scale)
        for layer in style.shadowLayers(canvasSize: canvasSize, opacity: opacity) {
            Self.castShadow(
                of: roundedPath(for: layout.cardRect, radius: layout.cardCornerRadius),
                in: shadowContext,
                offset: CGSize(width: 0, height: -layer.offset / scale),
                blur: layer.blur / scale,
                color: CGColor(gray: 0, alpha: layer.alpha),
                baseUnitsPerPoint: 1 / scale
            )
        }
        shadowContext.restoreGState()
        guard let image = shadowContext.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: small.width * scale, height: small.height * scale))
        context.restoreGState()
    }

    private func submitMorphMetal(
        screenFrame: CVPixelBuffer,
        sampleRects: [CGRect],
        layout: RecordingStudioLayout,
        motionBlur: StudioScreenMotionBlur,
        into destination: CVPixelBuffer
    ) -> StudioMetalScreenRenderer.Submission? {
        guard wallpaperVideo == nil, !sampleRects.isEmpty, !forceCoreGraphics, !metalFailed, !morphRendererFailed,
              StudioMetalScreenRenderer.shouldAccelerate(screenFrame: screenFrame, sampleRects: sampleRects)
        else { return nil }
        if morphRenderer == nil {
            morphRenderer = StudioMetalScreenRenderer(
                canvasSize: canvasSize, backdrop: plainBackdrop,
                cardPath: CGPath(rect: .zero, transform: nil), colorSpace: colorSpace
            )
        }
        let submitStart = CFAbsoluteTimeGetCurrent()
        defer { metalSeconds += CFAbsoluteTimeGetCurrent() - submitStart }
        guard let submission = morphRenderer?.submitMorph(
            screenFrame: screenFrame,
            sampleRects: sampleRects,
            card: StudioMetalScreenRenderer.MorphCard(
                rect: layout.cardRect, cornerRadius: layout.cardCornerRadius,
                opacity: layout.screenOpacity, shadow: cardShadow(for: layout),
                contactShadow: cardShadow(for: layout, layerIndex: 1)
            ),
            motionBlur: motionBlur, into: destination
        ) else {
            morphRendererFailed = true
            return nil
        }
        return submission
    }

    private func cardShadow(for layout: RecordingStudioLayout, layerIndex: Int = 0) -> StudioMorphShadow? {
        guard layout.screenOpacity > 0.001 else { return nil }
        let layers = style.shadowLayers(canvasSize: canvasSize, opacity: layout.screenOpacity)
        guard layers.indices.contains(layerIndex) else { return nil }
        let layer = layers[layerIndex]
        return StudioMorphShadow(offset: layer.offset, blur: layer.blur, alpha: layer.alpha)
    }

    private func drawMorphingScreen(
        _ screenImage: CGImage,
        editorTime: TimeInterval,
        opacity: CGFloat,
        motionBlur: StudioScreenMotionBlur,
        in context: CGContext
    ) {
        context.saveGState()
        context.setAlpha(opacity)
        let sample = frameLayout(at: editorTime).layout
        context.addPath(roundedPath(for: sample.cardRect, radius: sample.cardCornerRadius))
        context.clip()
        motionBlur.draw(
            screenImage, in: sample.frameRect(for: viewportFrame(at: editorTime)),
            canvasHeight: canvasSize.height, context: context
        )
        context.restoreGState()
    }

    private func drawMorphingCamera(_ cameraFrame: CVPixelBuffer, editorTime: TimeInterval, in context: CGContext) {
        guard let cameraImage = Self.makeImage(from: cameraFrame, colorSpace: colorSpace) else { return }
        let opacity = layout.cameraOpacity
        let times = morphCameraSampleTimes(at: editorTime)
        let bubble = layout.bubbleRect
        guard !times.isEmpty, bubble.width > 0, bubble.height > 0 else { return }
        let imageSize = CGSize(width: cameraImage.width, height: cameraImage.height)
        let minDimension = min(canvasSize.width, canvasSize.height)
        let path = roundedPath(for: bubble, radius: layout.bubbleCornerRadius, squircle: layout.cameraSquircle)

        Self.castShadow(
            of: path,
            in: context,
            offset: CGSize(width: 0, height: -minDimension * 0.009),
            blur: minDimension * 0.022,
            color: CGColor(gray: 0, alpha: 0.35 * opacity)
        )

        let layerRect = bubbleContentRect(for: layout)
        guard let content = renderLayer(covering: layerRect, draw: { layer in
            layer.saveGState()
            layer.addPath(path)
            layer.clip()
            layer.interpolationQuality = .medium
            for (index, time) in times.enumerated() {
                let sample = frameLayout(at: time).layout.bubbleRect
                guard sample.width > 0, sample.height > 0 else { continue }
                let fillRect = RecordingCameraCropGeometry.fillRect(
                    sourceSize: imageSize, destination: sample, crop: style.camera.pictureCrop
                )
                layer.setAlpha(index == 0 ? 1 : 1 / CGFloat(index + 1))
                layer.draw(cameraImage, in: flipped(fillRect))
            }
            layer.restoreGState()
            drawBubbleRim(layout: layout, in: layer)
        }) else { return }
        let framed = finishBubbleContent(content, layout: layout)
        context.saveGState()
        context.setAlpha(opacity)
        context.draw(framed, in: layerRect)
        context.restoreGState()
    }

    private static let maxMorphCameraSamples = 4

    private func morphCameraSampleTimes(at editorTime: TimeInterval) -> [TimeInterval] {
        let times = layout.cameraOpacity < 0.999
            ? [editorTime]
            : timing.sampleTimes(at: editorTime) { self.frameLayout(at: $0).layout.bubbleRect }
        guard times.count > Self.maxMorphCameraSamples else { return times }
        return (0..<Self.maxMorphCameraSamples).map { index in
            times[index * (times.count - 1) / (Self.maxMorphCameraSamples - 1)]
        }
    }

    private func renderMorphingCamera(
        _ cameraFrame: CVPixelBuffer, editorTime: TimeInterval, into destination: CVPixelBuffer
    ) -> Bool {
        guard bubbleFrame(for: layout) == .legacy, layout.cameraSquircle < 0.001 else { return false }
        guard !forceCoreGraphics, !morphCameraRendererFailed else { return false }
        if morphCameraRenderer == nil { morphCameraRenderer = StudioMorphCameraRenderer() }
        guard let renderer = morphCameraRenderer else {
            morphCameraRendererFailed = true
            return false
        }
        let bubble = layout.bubbleRect
        guard bubble.width > 0, bubble.height > 0 else { return true }
        let fillRects = morphCameraSampleTimes(at: editorTime).compactMap { time -> CGRect? in
            let sample = frameLayout(at: time).layout
            guard sample.bubbleRect.width > 0, sample.bubbleRect.height > 0 else { return nil }
            return cameraFillRect(cameraFrame, layout: sample)
        }
        guard !fillRects.isEmpty else { return true }
        let opacity = layout.cameraOpacity
        let minDimension = min(canvasSize.width, canvasSize.height)
        let start = CFAbsoluteTimeGetCurrent()
        defer { metalSeconds += CFAbsoluteTimeGetCurrent() - start }
        return renderer.render(
            camera: cameraFrame,
            fillRects: fillRects,
            bubble: StudioMorphCameraRenderer.Bubble(
                rect: bubble,
                cornerRadius: layout.bubbleCornerRadius,
                opacity: opacity,
                borderWidth: max(1, minDimension * 0.0018),
                borderAlpha: 0.25 * opacity,
                shadow: StudioMorphShadow(offset: minDimension * 0.009, blur: minDimension * 0.022, alpha: 0.35 * opacity)
            ),
            into: destination
        )
    }

    func showsCutout(at editorTime: TimeInterval) -> Bool {
        let layout = frameLayout(at: editorTime).layout
        return layout.cameraCutout > 0.001 && layout.cameraOpacity > 0.001 && layout.bubbleRect.width > 0
    }


    private func renderCutoutCamera(
        _ cameraFrame: CVPixelBuffer, cameraTime: TimeInterval, editorTime: TimeInterval,
        into destination: CVPixelBuffer
    ) -> Bool {
        guard !forceCoreGraphics, !morphCameraRendererFailed else { return false }
        let waitStart = CFAbsoluteTimeGetCurrent()
        let matte = cutoutMattes?.matte(at: cameraTime)
            ?? fallbackMattes?.matte(for: cameraFrame, time: cameraTime)
        cutoutWaitSeconds += CFAbsoluteTimeGetCurrent() - waitStart
        guard let matte else { return false }
        if morphCameraRenderer == nil { morphCameraRenderer = StudioMorphCameraRenderer() }
        guard let renderer = morphCameraRenderer else {
            morphCameraRendererFailed = true
            return false
        }
        let bubble = layout.bubbleRect
        guard bubble.width > 0, bubble.height > 0 else { return true }
        let fillRects = morphCameraSampleTimes(at: editorTime).compactMap { time -> CGRect? in
            let sample = frameLayout(at: time).layout
            guard sample.bubbleRect.width > 0, sample.bubbleRect.height > 0 else { return nil }
            return cameraFillRect(cameraFrame, layout: sample)
        }
        guard !fillRects.isEmpty else { return true }
        let opacity = layout.cameraOpacity
        let framed = 1 - layout.cameraCutout
        let picture = cameraFillRect(cameraFrame, layout: layout)
        let minDimension = min(canvasSize.width, canvasSize.height)
        let start = CFAbsoluteTimeGetCurrent()
        defer { metalSeconds += CFAbsoluteTimeGetCurrent() - start }
        return renderer.render(
            camera: cameraFrame,
            fillRects: fillRects,
            bubble: StudioMorphCameraRenderer.Bubble(
                rect: bubble,
                cornerRadius: layout.bubbleCornerRadius,
                opacity: opacity,
                borderWidth: max(1, minDimension * 0.0018),
                borderAlpha: 0.25 * opacity * framed,
                shadow: StudioMorphShadow(
                    offset: minDimension * 0.009, blur: minDimension * 0.022, alpha: 0.35 * opacity * framed
                )
            ),
            cutout: StudioMorphCameraRenderer.Cutout(
                matte: matte,
                amount: layout.cameraCutout,
                feather: StudioCutoutStyle.feather(picture: picture, canvas: canvasSize),
                picture: picture,
                shadowAlpha: StudioCutoutStyle.shadowAlpha * opacity * layout.cameraCutout
            ),
            into: destination
        )
    }

    private func lockedContext(for destination: CVPixelBuffer) -> CGContext? {
        guard let base = CVPixelBufferGetBaseAddress(destination),
              let context = CGContext(
                data: base,
                width: CVPixelBufferGetWidth(destination),
                height: CVPixelBufferGetHeight(destination),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(destination),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        return context
    }

    private func submitMetal(
        screenFrame: CVPixelBuffer,
        sampleRects: [CGRect],
        settled: SettledLayout?,
        layout: RecordingStudioLayout,
        motionBlur: StudioScreenMotionBlur,
        into destination: CVPixelBuffer
    ) -> StudioMetalScreenRenderer.Submission? {
        guard wallpaperVideo == nil, let settled, !sampleRects.isEmpty, !forceCoreGraphics, !metalFailed,
              StudioMetalScreenRenderer.shouldAccelerate(screenFrame: screenFrame, sampleRects: sampleRects)
        else { return nil }
        let resources = resources(for: settled, layout: layout)
        if resources.metalRenderer == nil {
            resources.metalRenderer = StudioMetalScreenRenderer(
                canvasSize: canvasSize, backdrop: resources.backdrop,
                cardPath: roundedPath(for: layout.cardRect, radius: layout.cardCornerRadius), colorSpace: colorSpace
            )
        }
        let submitStart = CFAbsoluteTimeGetCurrent()
        defer { metalSeconds += CFAbsoluteTimeGetCurrent() - submitStart }
        guard let submission = resources.metalRenderer?.submit(
            screenFrame: screenFrame, sampleRects: sampleRects, motionBlur: motionBlur, into: destination
        ) else {
            metalFailed = true
            return nil
        }
        return submission
    }

    private func drawCameraBubble(
        _ cameraFrame: CVPixelBuffer, resources: LayoutResources,
        submission: StudioCameraBubbleScaler.Submission?, in context: CGContext
    ) {
        if resources.bubbleContentSource !== cameraFrame {
            resources.bubbleContentImage = renderBubbleContent(cameraFrame, resources: resources, submission: submission)
            resources.bubbleContentSource = resources.bubbleContentImage == nil ? nil : cameraFrame
        }
        guard let content = resources.bubbleContentImage else { return }
        if let shadow = bubbleShadow(for: resources) {
            context.draw(shadow.image, in: shadow.rect)
        }
        context.draw(content, in: bubbleContentRect(for: resources.layout))
    }

    private func bubbleContentRect(for layout: RecordingStudioLayout) -> CGRect {
        flipped(layout.bubbleRect).integral
    }

    private func bubbleFrame(for layout: RecordingStudioLayout) -> RecordingCameraPreviewFrame {
        layout.cameraCutout > 0.001 || layout.cameraBubble < 0.5 ? .legacy : style.camera.previewFrame
    }

    private func drawBubbleRim(layout: RecordingStudioLayout, in context: CGContext) {
        let frame = bubbleFrame(for: layout)
        guard frame != .softBlur else { return }
        let bubble = layout.bubbleRect
        context.saveGState()
        if frame == .standard {
            let path = roundedPath(for: bubble, radius: layout.bubbleCornerRadius, squircle: layout.cameraSquircle)
            context.addPath(path)
            context.clip()
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.26))
            context.setLineWidth(StudioCameraBubbleFrame.rimWidth(size: bubble.size) * 2)
        } else {
            context.addPath(roundedPath(for: bubble.insetBy(dx: 0.5, dy: 0.5), radius: layout.bubbleCornerRadius,
                                        squircle: layout.cameraSquircle))
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.25))
            context.setLineWidth(max(1, min(canvasSize.width, canvasSize.height) * 0.0018))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func finishBubbleContent(_ image: CGImage, layout: RecordingStudioLayout) -> CGImage {
        guard bubbleFrame(for: layout) == .softBlur else { return image }
        return StudioCameraBubbleFrame.soften(image, size: bubbleContentRect(for: layout).size,
                                              radius: layout.bubbleCornerRadius, squircle: layout.cameraSquircle,
                                              canvasWidth: canvasSize.width) ?? image
    }

    private func bubbleShadow(for resources: LayoutResources) -> (image: CGImage, rect: CGRect)? {
        if let cached = resources.bubbleShadow { return cached }
        let layout = resources.layout
        let minDimension = min(canvasSize.width, canvasSize.height)
        let blur = minDimension * 0.022
        let offset = minDimension * 0.009
        let rect = bubbleContentRect(for: layout)
            .insetBy(dx: -(blur * 2 + offset), dy: -(blur * 2 + offset))
            .intersection(CGRect(origin: .zero, size: canvasSize))
            .integral
        let image = renderLayer(covering: rect, draw: { context in
            Self.castShadow(
                of: roundedPath(for: layout.bubbleRect, radius: layout.bubbleCornerRadius, squircle: layout.cameraSquircle),
                in: context,
                offset: CGSize(width: 0, height: -offset),
                blur: blur,
                color: CGColor(gray: 0, alpha: 0.35)
            )
        })
        let shadow = image.map { ($0, rect) }
        resources.bubbleShadow = .some(shadow)
        return shadow
    }

    private func cameraScaler(for resources: LayoutResources) -> StudioCameraBubbleScaler? {
        if let cached = resources.cameraScaler { return cached }
        let scaler = forceCoreGraphics
            ? nil
            : StudioCameraBubbleScaler(size: bubbleContentRect(for: resources.layout).size, colorSpace: colorSpace)
        resources.cameraScaler = .some(scaler)
        return scaler
    }

    private func cameraFillRect(_ cameraFrame: CVPixelBuffer, layout: RecordingStudioLayout) -> CGRect {
        RecordingCameraCropGeometry.fillRect(
            sourceSize: CGSize(width: CVPixelBufferGetWidth(cameraFrame), height: CVPixelBufferGetHeight(cameraFrame)),
            destination: layout.bubbleRect,
            crop: style.camera.pictureCrop
        )
    }

    private func prepareCamera(
        _ cameraFrame: CVPixelBuffer, resources: LayoutResources
    ) -> StudioCameraBubbleScaler.Submission? {
        guard resources.bubbleContentSource !== cameraFrame else { return nil }
        if resources.scheduledCameraSource === cameraFrame { return resources.scheduledCameraSubmission }
        let layerRect = bubbleContentRect(for: resources.layout)
        let fillRect = cameraFillRect(cameraFrame, layout: resources.layout)
        let submission = cameraScaler(for: resources)?.submit(
            cameraFrame,
            fillRect: fillRect.offsetBy(dx: -layerRect.minX, dy: -(canvasSize.height - layerRect.maxY))
        )
        resources.scheduledCameraSource = submission == nil ? nil : cameraFrame
        resources.scheduledCameraSubmission = submission
        return submission
    }

    private func renderBubbleContent(
        _ cameraFrame: CVPixelBuffer, resources: LayoutResources,
        submission: StudioCameraBubbleScaler.Submission?
    ) -> CGImage? {
        let layout = resources.layout
        let bubble = layout.bubbleRect
        let imageSize = CGSize(width: CVPixelBufferGetWidth(cameraFrame), height: CVPixelBufferGetHeight(cameraFrame))
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let fillRect = cameraFillRect(cameraFrame, layout: layout)
        let layerRect = bubbleContentRect(for: layout)
        let scaledCamera = submission.flatMap { cameraScaler(for: resources)?.image(for: $0) }
        let cameraImage = scaledCamera == nil ? Self.makeImage(from: cameraFrame, colorSpace: colorSpace) : nil
        guard scaledCamera != nil || cameraImage != nil else { return nil }
        guard let content = renderLayer(covering: layerRect, draw: { context in
            context.saveGState()
            context.addPath(roundedPath(for: bubble, radius: layout.bubbleCornerRadius, squircle: layout.cameraSquircle))
            context.clip()
            if let scaledCamera {
                context.draw(scaledCamera, in: layerRect)
            } else if let cameraImage {
                context.draw(cameraImage, in: flipped(fillRect))
            }
            context.restoreGState()

            drawBubbleRim(layout: layout, in: context)
        }) else { return nil }
        return finishBubbleContent(content, layout: layout)
    }

    private func renderLayer(covering rect: CGRect, draw: (CGContext) -> Void) -> CGImage? {
        guard rect.width >= 1, rect.height >= 1,
              let context = CGContext(
                data: nil,
                width: Int(rect.width),
                height: Int(rect.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: -rect.minX, y: -rect.minY)
        draw(context)
        return context.makeImage()
    }

    private func drawPointer(editorTime: TimeInterval, in context: CGContext) {
        guard let pointerTimeline,
              let pointer = pointerTimeline.frame(at: editorTime) else {
            return
        }

        let drawRect = layout.frameRect(for: viewportFrame(at: editorTime))
        let tip = CGPoint(
            x: drawRect.minX + pointer.location.x * drawRect.width,
            y: canvasSize.height - (drawRect.minY + pointer.location.y * drawRect.height)
        )

        let resolvedArtwork = artwork(for: pointer, in: pointerTimeline)
        var pressGeometry: (tip: CGPoint, effect: RecordingClickEffectGeometry)?
        if showsPressEffects,
           let press = clickEffectSettings.effect == .impact ? pointer.press : pointer.clickPress {
            let location = clickEffectSettings.location(for: press, cursor: pointer.location)
            pressGeometry = (
                CGPoint(
                    x: drawRect.minX + location.x * drawRect.width,
                    y: canvasSize.height - (drawRect.minY + location.y * drawRect.height)
                ),
                clickEffectSettings.geometry(
                    press: press,
                    referenceHeight: layout.contentFillSize.height,
                    cursorScale: pointerScale,
                    cursorHeight: layout.contentFillSize.height * PointerArtworkMetrics.heightRatio
                        * pointerScale * (resolvedArtwork?.intrinsicScale ?? 1)
                )
            )
        }
        var artworkPlacement: (image: CGImage, rect: CGRect, transform: CGAffineTransform)?
        var material: (material: PointerMaterial, radius: CGFloat)?
        if let resolved = resolvedArtwork {
            let height = layout.contentFillSize.height
                * PointerArtworkMetrics.heightRatio
                * pointerScale
                * resolved.intrinsicScale
            let size = CGSize(width: height * resolved.aspectRatio, height: height)
            let interactionScale = CGFloat(max(pointer.magnification, 0.1))
            if let pointerMaterial = resolved.material {
                material = (pointerMaterial, size.width * PointerShape.circleRadiusRatio * interactionScale)
            }
            let transform = CGAffineTransform(translationX: tip.x, y: tip.y)
                .rotated(by: resolved.leans ? -CGFloat(pointer.tiltDegrees * .pi / 180) : 0)
                .scaledBy(x: interactionScale, y: interactionScale)
            artworkPlacement = (
                resolved.image,
                CGRect(
                    x: -resolved.anchor.x * size.width,
                    y: -(1 - resolved.anchor.y) * size.height,
                    width: size.width,
                    height: size.height
                ),
                transform
            )
        }

        var bounds = CGRect.null
        if let pressGeometry {
            bounds = bounds.union(pressGeometry.effect.bounds.offsetBy(dx: pressGeometry.tip.x, dy: pressGeometry.tip.y))
        }
        if let artworkPlacement {
            let shadowPadding = resolvedArtwork?.needsCursorShadow == true
                ? RecordingCursorShadowMetrics.padding * CGFloat(max(pointer.magnification, 0.1)) : 0
            bounds = bounds.union(
                artworkPlacement.rect.applying(artworkPlacement.transform)
                    .insetBy(dx: -shadowPadding, dy: -shadowPadding)
            )
        }
        guard !bounds.isNull else { return }
        let card = flipped(layout.cardRect)
        let radius = min(layout.cardCornerRadius, min(card.width, card.height) / 2)
        let paddedBounds = bounds.insetBy(dx: -2, dy: -2)
        let needsClip = !card.insetBy(dx: radius, dy: 0).contains(paddedBounds)
            && !card.insetBy(dx: 0, dy: radius).contains(paddedBounds)

        context.saveGState()
        context.setAlpha(overlayOpacity)
        if needsClip {
            context.addPath(roundedPath(for: layout.cardRect, radius: layout.cardCornerRadius))
            context.clip()
        }
        if let pressGeometry {
            let (pressTip, effect) = pressGeometry
            effect.draw(in: context, at: pressTip, settings: clickEffectSettings)
        }

        if let artworkPlacement {
            context.setAlpha(CGFloat(min(max(pointer.opacity, 0), 1)) * overlayOpacity)
            if let material {
                pointerMaterialRenderer.draw(material.material, center: tip, radius: material.radius, in: context)
            }
            context.concatenate(artworkPlacement.transform)
            if resolvedArtwork?.usesNearestNeighborSampling == true {
                context.interpolationQuality = .none
            }
            if resolvedArtwork?.needsCursorShadow == true {
                let transform = artworkPlacement.transform
                let offsetX = RecordingCursorShadowMetrics.offsetX
                let offsetY = -RecordingCursorShadowMetrics.offsetY
                let scale = sqrt(transform.a * transform.a + transform.b * transform.b)
                context.setShadow(
                    offset: CGSize(
                        width: transform.a * offsetX + transform.c * offsetY,
                        height: transform.b * offsetX + transform.d * offsetY
                    ),
                    blur: RecordingCursorShadowMetrics.blurRadius * scale,
                    color: CGColor(gray: 0, alpha: RecordingCursorShadowMetrics.opacity)
                )
            }
            context.draw(artworkPlacement.image, in: artworkPlacement.rect)
        }
        context.restoreGState()
    }

    private func drawKeystrokeCaption(at time: TimeInterval, in context: CGContext) {
        guard let caption = keystrokeTimeline?.frame(at: time) else { return }
        RecordingKeystrokeCaptionRenderer.draw(
            caption, appearance: keystrokeAppearance, fallbackPlacement: keystrokePlacement,
            card: layout.cardRect, canvasHeight: canvasSize.height, opacity: Double(overlayOpacity), in: context
        )
    }

    private func drawSpeedBadge(at time: TimeInterval, in context: CGContext) {
        guard let speedBadgeTimeline,
              let badge = speedBadgeTimeline.frame(at: time),
              badge.opacity > 0.001 else {
            return
        }

        let metrics = SpeedBadgeMetrics(cardHeight: layout.cardRect.height)
        let font = Self.captionFont(size: metrics.fontSize)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: badge.title, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ]))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        guard textWidth > 0 else { return }

        let badgeSize = CGSize(
            width: metrics.badgeWidth(textWidth: textWidth),
            height: ascent + descent + metrics.paddingVertical * 2
        )
        let origin = metrics.badgeOrigin(
            badgeSize: badgeSize,
            cardRect: layout.cardRect,
            placement: speedBadgePlacement
        )
        let badgeRect = flipped(CGRect(origin: origin, size: badgeSize))

        context.saveGState()
        context.setAlpha(CGFloat(badge.opacity) * overlayOpacity)
        context.translateBy(x: badgeRect.midX, y: badgeRect.midY)
        context.scaleBy(x: CGFloat(badge.scale), y: CGFloat(badge.scale))
        context.translateBy(x: -badgeRect.midX, y: -badgeRect.midY)

        let radius = min(metrics.cornerRadius, badgeRect.height / 2)
        context.addPath(CGPath(
            roundedRect: badgeRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: 0, alpha: SpeedBadgeMetrics.backgroundAlpha))
        context.fillPath()

        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: badgeRect.minX + metrics.paddingHorizontal,
            y: badgeRect.midY - (ascent - descent) / 2
        )
        CTLineDraw(line, context)

        context.setLineWidth(metrics.chevronLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let firstChevronX = badgeRect.minX + metrics.paddingHorizontal + textWidth + metrics.textGap
        for index in 0..<SpeedBadgeMetrics.chevronCount {
            context.addPath(metrics.chevronPath(
                minX: firstChevronX + metrics.chevronAdvance * CGFloat(index),
                midY: badgeRect.midY
            ))
            context.setStrokeColor(CGColor(gray: 1, alpha: CGFloat(badge.chevronAlpha(index))))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawSubtitleBar(at time: TimeInterval, in context: CGContext) {
        if subtitleStyle.preset != .upshot {
            guard let captionTimeline,
                  let frame = StudioCaptionRenderer.layout(timeline: captionTimeline, style: subtitleStyle, canvasSize: captionCanvasSize, time: time) else { return }
            context.saveGState()
            context.translateBy(x: 0, y: canvasSize.height)
            context.scaleBy(x: 1, y: -1)
            context.scaleBy(x: canvasSize.width / max(1, captionCanvasSize.width), y: canvasSize.height / max(1, captionCanvasSize.height))
            StudioCaptionRenderer.draw(frame, style: subtitleStyle, time: time, in: context)
            context.restoreGState()
            return
        }
        guard let subtitleTimeline,
              let text = subtitleTimeline.text(at: time) else {
            return
        }

        let metrics = SubtitleBarMetrics(canvasSize: canvasSize, style: subtitleStyle)
        let maximumTextWidth = metrics.maximumTextWidth(canvasWidth: canvasSize.width)

        var fontSize = metrics.fontSize
        var wrappedLines: [CTLine] = []
        for _ in 0..<3 {
            let font = Self.captionFont(size: fontSize)
            let attributed = subtitleAttributedText(plainText: text, at: time, font: font)
            wrappedLines = Self.wrapLines(attributed, width: maximumTextWidth)
            if wrappedLines.count <= SubtitleBarMetrics.maximumLineCount || fontSize <= 11 {
                break
            }
            fontSize *= CGFloat(SubtitleBarMetrics.maximumLineCount) / CGFloat(wrappedLines.count)
        }
        guard !wrappedLines.isEmpty else { return }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidths = wrappedLines.map {
            CGFloat(CTLineGetTypographicBounds($0, &ascent, &descent, &leading))
        }
        guard let widestLine = lineWidths.max(), widestLine > 0 else { return }
        let lineAdvance = (ascent + descent) * SubtitleBarMetrics.lineSpacingFactor
        let textHeight = ascent + descent + lineAdvance * CGFloat(wrappedLines.count - 1)

        let barSize = CGSize(
            width: widestLine + metrics.paddingHorizontal * 2,
            height: textHeight + metrics.paddingVertical * 2
        )
        let barCenterY = canvasSize.height * CGFloat(subtitleStyle.clampedVerticalPosition)
        let origin = CGPoint(
            x: canvasSize.width / 2 - barSize.width / 2,
            y: barCenterY - barSize.height / 2
        )
        let barRect = flipped(CGRect(origin: origin, size: barSize))

        context.saveGState()
        let radius = min(metrics.cornerRadius, barRect.height / 2)
        context.addPath(CGPath(
            roundedRect: barRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        ))
        context.setFillColor(CGColor(gray: 0, alpha: SubtitleBarMetrics.backgroundAlpha))
        context.fillPath()

        context.textMatrix = .identity
        let firstBaseline = barRect.maxY - metrics.paddingVertical - ascent
        for (index, wrappedLine) in wrappedLines.enumerated() {
            context.textPosition = CGPoint(
                x: barRect.midX - lineWidths[index] / 2,
                y: firstBaseline - lineAdvance * CGFloat(index)
            )
            CTLineDraw(wrappedLine, context)
        }
        context.restoreGState()
    }

    private static func wrapLines(
        _ attributed: NSAttributedString,
        width: CGFloat
    ) -> [CTLine] {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(
            rect: CGRect(x: 0, y: 0, width: max(24, width), height: 100_000),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )
        return (CTFrameGetLines(frame) as? [CTLine]) ?? []
    }

    private func subtitleAttributedText(
        plainText: String,
        at time: TimeInterval,
        font: CTFont
    ) -> NSAttributedString {
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

        guard subtitleStyle.highlightsSpokenWord,
              captionTimeline?.cue(at: time)?.hasRecognizedTiming != false,
              let karaokeTimeline,
              let karaokeLine = karaokeTimeline.line(at: time),
              !karaokeLine.words.isEmpty else {
            return NSAttributedString(string: plainText, attributes: [
                fontKey: font,
                colorKey: CGColor(gray: 1, alpha: 1)
            ])
        }

        let text = NSMutableAttributedString()
        for (index, word) in karaokeLine.words.enumerated() {
            let color: CGColor
            if index == karaokeLine.activeIndex {
                color = SubtitleBarMetrics.karaokeAccent
            } else if index < karaokeLine.spokenCount {
                color = CGColor(gray: 1, alpha: 1)
            } else {
                color = CGColor(gray: 1, alpha: SubtitleBarMetrics.karaokeUpcomingAlpha)
            }
            text.append(NSAttributedString(
                string: index > 0 ? " \(word)" : word,
                attributes: [fontKey: font, colorKey: color]
            ))
        }
        return text
    }

    private static func captionFont(size: CGFloat) -> CTFont {
        let descriptor = NSFont.systemFont(ofSize: size, weight: .semibold).fontDescriptor
        let rounded = descriptor.withDesign(.rounded) ?? descriptor
        return CTFontCreateWithFontDescriptor(rounded as CTFontDescriptor, size, nil)
    }

    private func artwork(
        for pointer: PointerFrame,
        in timeline: PointerTimeline
    ) -> (
        image: CGImage,
        anchor: CGPoint,
        aspectRatio: CGFloat,
        intrinsicScale: CGFloat,
        material: PointerMaterial?,
        leans: Bool,
        usesNearestNeighborSampling: Bool,
        needsCursorShadow: Bool
    )? {
        if let resolved = timeline.artwork(id: pointer.artworkID),
           let image = artworkImage(for: resolved) {
            return (
                image,
                resolved.normalizedAnchor,
                resolved.aspectRatio,
                resolved.intrinsicScale,
                PointerShape(artworkID: resolved.artworkID)?.material,
                resolved.leans,
                resolved.usesNearestNeighborSampling,
                resolved.needsCursorShadow
            )
        }
        return nil
    }

    private func artworkImage(for artwork: PointerArtwork) -> CGImage? {
        if let cached = artworkImageCache[artwork.artworkID] {
            return cached
        }
        guard let source = CGImageSourceCreateWithData(artwork.imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        artworkImageCache[artwork.artworkID] = image
        return image
    }

    private func flipped(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: canvasSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func roundedPath(for rect: CGRect, radius: CGFloat, squircle: CGFloat = 0) -> CGPath {
        let flippedRect = flipped(rect)
        if squircle > 0.001 { return StudioCameraBubbleFrame.path(in: flippedRect, radius: radius, squircle: squircle) }
        let boundedRadius = min(radius, min(flippedRect.width, flippedRect.height) / 2)
        guard boundedRadius > 0.5 else { return CGPath(rect: flippedRect, transform: nil) }
        return CGPath(
            roundedRect: flippedRect,
            cornerWidth: boundedRadius,
            cornerHeight: boundedRadius,
            transform: nil
        )
    }

    private static func makeImage(from pixelBuffer: CVPixelBuffer, colorSpace: CGColorSpace) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: base,
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }
        return context.makeImage()
    }

    private static func renderBackdrop(
        canvasSize: CGSize,
        layout: RecordingStudioLayout?,
        style: RecordingStudioStyle,
        colorSpace: CGColorSpace,
        wallpaperFrame: CGImage? = nil
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        let canvasRect = CGRect(origin: .zero, size: canvasSize)

        switch style.resolvedBackground(canvasSize: canvasSize) {
        case .none:
            context.setFillColor(CGColor(gray: 0.04, alpha: 1))
            context.fill(canvasRect)
        case .solid(let color):
            context.setFillColor(CGColor(
                colorSpace: colorSpace,
                components: [color.red, color.green, color.blue, color.alpha]
            ) ?? CGColor(gray: 0, alpha: 1))
            context.fill(canvasRect)
        case .gradient(let gradient):
            let cgColors = gradient.colors.map { color in
                CGColor(
                    colorSpace: colorSpace,
                    components: [color.red, color.green, color.blue, color.alpha]
                ) ?? CGColor(gray: 0, alpha: 1)
            }
            if let cgGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: cgColors as CFArray,
                locations: nil
            ) {
                let start = CGPoint(
                    x: gradient.startPoint.x * canvasSize.width,
                    y: canvasSize.height - gradient.startPoint.y * canvasSize.height
                )
                let end = CGPoint(
                    x: gradient.endPoint.x * canvasSize.width,
                    y: canvasSize.height - gradient.endPoint.y * canvasSize.height
                )
                context.drawLinearGradient(cgGradient, start: start, end: end, options: [
                    .drawsBeforeStartLocation,
                    .drawsAfterEndLocation
                ])
            }
        case .customWallpaper(let wallpaper):
            if let wallpaperFrame {
                if let image = RecordingStudioBackgroundBlur.render(
                    wallpaperFrame, canvasSize: canvasSize, amount: style.backgroundBlur
                ) {
                    context.draw(image, in: canvasRect)
                }
            } else if wallpaper.isVideo {
                context.setFillColor(CGColor(gray: 0.04, alpha: 1))
                context.fill(canvasRect)
            } else if style.backgroundBlur > 0, let image = RecordingStudioBackgroundBlur.wallpaper(
                at: wallpaper.url, canvasSize: canvasSize, amount: style.backgroundBlur
            ) {
                context.draw(image, in: canvasRect)
            } else if let source = CGImageSourceCreateWithURL(wallpaper.url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, [
                   kCGImageSourceShouldCache: false
               ] as CFDictionary) {
                let imageSize = CGSize(width: image.width, height: image.height)
                let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
                let fillSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                let fillRect = CGRect(
                    x: (canvasSize.width - fillSize.width) / 2,
                    y: (canvasSize.height - fillSize.height) / 2,
                    width: fillSize.width,
                    height: fillSize.height
                )
                context.draw(image, in: fillRect)
            } else {
                context.setFillColor(CGColor(gray: 0.04, alpha: 1))
                context.fill(canvasRect)
            }
        }

        if let layout, style.shadow > 0, style.background != .none {
            let cardRect = CGRect(
                x: layout.cardRect.minX,
                y: canvasSize.height - layout.cardRect.maxY,
                width: layout.cardRect.width,
                height: layout.cardRect.height
            )
            let radius = min(layout.cardCornerRadius, min(cardRect.width, cardRect.height) / 2)
            let path = radius > 0.5
                ? CGPath(roundedRect: cardRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                : CGPath(rect: cardRect, transform: nil)

            for layer in style.shadowLayers(canvasSize: canvasSize) {
                castShadow(
                    of: path,
                    in: context,
                    offset: CGSize(width: 0, height: -layer.offset),
                    blur: layer.blur,
                    color: CGColor(gray: 0, alpha: layer.alpha)
                )
            }
        }

        return context.makeImage()
    }
}
