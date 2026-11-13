
import AppKit
import AVFoundation
import CoreGraphics

@MainActor
enum RecordingSessionRenderer {
    private enum RenderError: LocalizedError {
        case missingCameraTrack

        var errorDescription: String? {
            "The camera recording does not contain a readable video track."
        }
    }

    static func ensureDeliverable(
        for session: RecordingSession,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let manifest = session.loadCaptureManifest()
        let pointerSynthesized = manifest?.pointerSynthesized == true
        let editDocument = session.effectiveEditDocument()
        guard session.hasCamera || pointerSynthesized || editDocument != nil
            || RecordingExportOptionStore.load(from: session.directoryURL) != nil
            || RecordingExportAppearanceStore.load(from: session.directoryURL) != nil else {
            return session.screenURL
        }
        if RecordingExportOptionStore.load(from: session.directoryURL) == nil,
           RecordingExportAppearanceStore.load(from: session.directoryURL) == nil,
           let existing = session.freshFinalURL(matching: editDocument) { return existing }

        let configuration = try await makeConfiguration(for: session)
        let temporaryURL = try await RecordingStudioExporter().export(configuration) { progress in
            onProgress?(progress)
        }
        do {
            return try session.installFinalVideo(
                movingFrom: temporaryURL,
                renderedFrom: editDocument
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func makeConfiguration(
        for session: RecordingSession
    ) async throws -> RecordingStudioExporter.Configuration {
        let manifest = session.loadCaptureManifest()
        let pointerSynthesized = manifest?.pointerSynthesized == true
        let editDocument = session.effectiveEditDocument()
        let asset = AVURLAsset(url: session.screenURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }

        var cameraAspect: CGFloat?
        if session.hasCamera {
            let cameraAsset = AVURLAsset(url: session.cameraURL)
            guard try await !cameraAsset.loadTracks(withMediaType: .video).isEmpty else {
                throw RenderError.missingCameraTrack
            }
            cameraAspect = await RecordingCameraVideo.aspect(of: session.cameraURL)
        }

        let canvasSize = try await outputSize(for: asset, manifest: manifest)
        let recordingPointScale = max(manifest?.pixelScale ?? 1, 1)
        let recordingPointSize = CGSize(
            width: canvasSize.width / CGFloat(recordingPointScale),
            height: canvasSize.height / CGFloat(recordingPointScale)
        )
        let capture = PointerStreamSanitizer.sanitize(
            session.loadPointerCapture() ?? PointerCaptureFile(),
            options: PointerSanitizeOptions(
                recordingSizeInPoints: recordingPointSize
            )
        ).sanitizedCapture
        let document = editDocument
        var style = document?.style.value ?? RecordingStudioStyle()
        style.camera.isVisible = session.hasCamera && (document?.style.value.camera.isVisible ?? true)
        let zoomEnabled = document?.zoomEnabled ?? true
        let zoomCues = document?.zoomCues
            ?? ZoomCueSynthesizer.cues(from: capture, duration: duration)
        let clipTimeline: RecordingClipTimeline
        if let clips = document?.clips, !clips.isEmpty {
            clipTimeline = RecordingClipTimeline(segments: clips).normalized(to: duration)
        } else {
            clipTimeline = .legacyTrim(
                start: document?.trimStart,
                end: document?.trimEnd,
                sourceDuration: duration
            )
        }
        let viewportTimeline = zoomEnabled
            ? ViewportTimeline.build(cues: zoomCues, capture: capture, clipTimeline: clipTimeline)
            : .identity
        let cameraLayoutTimeline = RecordingCameraLayoutTimeline.build(
            defaultLayout: style.camera.layout,
            cues: document?.cameraLayoutCues ?? [],
            clipTimeline: clipTimeline
        )
        let showsPressEffects = pointerSynthesized
            && manifest?.pressEffectsBaked == false
            && (document?.showsClickEffects ?? manifest?.pressEffectsEnabled ?? true)
        let showsKeystrokes = (document?.showsKeystrokes ?? true) && !capture.keystrokes.isEmpty

        let hasPointerData = !capture.travel.isEmpty || !capture.presses.isEmpty
        let pointerTimeline = hasPointerData
            ? PointerTimeline.build(
                capture: capture,
                duration: duration,
                recordingSizeInPoints: recordingPointSize,
                fallbackArtwork: PointerArtworkCapture.defaultArtwork(),
                clipTimeline: clipTimeline
            )
            : nil

        let showsSubtitles = document?.showsSubtitles ?? true
        let cues = document?.subtitleCues ?? []
        let words = document?.subtitleWords ?? []

        let aspect = document?.exportAspectPreset ?? .original
        let aspectMode = document?.exportAspectContentMode ?? .fill
        let reframe: ReframeTrack? = aspectMode == .fill
            ? ReframeTrack.build(
                preset: aspect,
                sourceSize: canvasSize,
                viewportTimeline: viewportTimeline,
                duration: clipTimeline.duration
            ) { editorTime in
                pointerTimeline?.location(at: editorTime)
            }
            : nil
        let fitContentAspect: CGFloat? =
            (aspect == .original || aspectMode == .fit) && canvasSize.height > 0
                ? canvasSize.width / canvasSize.height
                : nil
        let exportCanvasSize = aspect == .original
            ? RecordingStudioLayout.originalCanvasSize(
                sourceSize: canvasSize,
                style: style,
                contentCropRect: document?.normalizedVideoCropRect ?? RecordingVideoCropGeometry.unit
            )
            : aspect.canvasSize(for: canvasSize)
        let videoCropRect = document?.normalizedVideoCropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let appearance = RecordingExportAppearanceStore.load(from: session.directoryURL) ?? RecordingExportAppearance()
        let motionTimeline = RecordingStudioMotionTimeline.build(
            canvasSize: exportCanvasSize,
            style: style,
            usesUniformPadding: aspect == .original,
            contentAspect: reframe?.sourceAspect ?? fitContentAspect,
            contentMode: fitContentAspect != nil && reframe == nil ? .fit : .fill,
            contentCropRect: videoCropRect,
            showsCamera: style.camera.isVisible,
            cameraAspect: cameraAspect ?? RecordingCameraLayoutResolver.defaultCameraAspect,
            layoutTimeline: cameraLayoutTimeline,
            cues: zoomEnabled ? zoomCues : [],
            capture: capture,
            clipTimeline: clipTimeline,
            zoomAnimationStyle: appearance.zoomAnimationStyle,
            reframe: reframe
        )

        var configuration = RecordingStudioExporter.Configuration(
            screenURL: session.screenURL,
            cameraURL: style.camera.isVisible && cameraLayoutTimeline.usesCamera ? session.cameraURL : nil,
            cameraOffset: manifest?.cameraLeadIn ?? 0,
            cameraAspect: cameraAspect,
            style: style,
            cameraLayoutTimeline: cameraLayoutTimeline,
            viewportTimeline: viewportTimeline,
            pointerTimeline: pointerSynthesized
                ? pointerTimeline?.mappingArtwork {
                    $0.styled(style.cursorStyle, inverted: style.invertsCursor)
                }
                : nil,
            showsPressEffects: showsPressEffects,
            keystrokeTimeline: showsKeystrokes
                ? KeystrokeCaptionTimeline(events: capture.keystrokes.filter(appearance.keystrokes.filter.includes))
                : nil,
            keystrokePlacement: document?.keystrokePlacement ?? .bottomCenter,
            speedBadgeTimeline: document?.showsSpeedBadge == true
                ? SpeedBadgeTimeline(clipTimeline: clipTimeline)
                : nil,
            speedBadgePlacement: document?.speedBadgePlacement ?? .topRight,
            subtitleTimeline: showsSubtitles && !cues.isEmpty
                ? SubtitleTimeline(cues: cues)
                : nil,
            subtitleStyle: document?.subtitleStyle ?? SubtitleBarStyle(),
            karaokeTimeline: showsSubtitles && !cues.isEmpty && !words.isEmpty
                ? KaraokeTimeline(cues: cues, words: words)
                : nil,
            canvasSize: exportCanvasSize,
            videoCropRect: videoCropRect,
            clipTimeline: clipTimeline,
            exportSettings: document?.exportSettings ?? VideoCompressionSettings(),
            audioVolume: document?.audioVolume ?? 1,
            reframe: reframe,
            fitContentAspect: fitContentAspect,
            usesUniformPadding: aspect == .original,
            motionTimeline: motionTimeline,
            textOverlays: document?.textOverlays ?? [],
            redactions: document?.redactions ?? [],
            imageOverlays: document?.imageOverlays ?? [],
            audioClips: document?.audioClips ?? [],
            mediaDirectory: session.directoryURL.appendingPathComponent("media", isDirectory: true)
        )
        configuration.appearance = appearance
        configuration.deliveryOptions = RecordingExportOptionStore.load(from: session.directoryURL) ?? RecordingExportDeliveryOptions()
        configuration.deliveryOptions.format = .video
        configuration.sourcePixelScale = manifest?.pixelScale ?? 1
        configuration.recordedAudioTrackNames = [
            manifest?.includesSystemAudio == true ? "System Audio" : nil,
            manifest?.includesMicrophone == true ? "Microphone" : nil
        ].compactMap { $0 }
        return configuration
    }

    static func presentFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The camera video could not be added"
        alert.informativeText = "Your screen, camera, and audio masters are safe in the recording project, but Upshot could not create the combined video: \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func outputSize(
        for asset: AVURLAsset,
        manifest: CaptureManifest?
    ) async throws -> CGSize {
        if let manifest, manifest.pixelWidth > 0, manifest.pixelHeight > 0 {
            return CGSize(width: manifest.pixelWidth, height: manifest.pixelHeight)
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = size.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}
