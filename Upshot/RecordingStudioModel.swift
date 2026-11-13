
import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Observation

enum RecordingTranscriptionState: Equatable {
    case idle
    case transcribing
    case failed(String)

    var isTranscribing: Bool {
        self == .transcribing
    }
}

enum RecordingStudioExportState: Equatable {
    case idle
    case exporting(progress: Double)
    case finished(URL)
    case failed(String)

    var isExporting: Bool {
        if case .exporting = self { return true }
        return false
    }
}

enum RecordingStudioShareState: Equatable {
    case idle
    case rendering(progress: Double)
    case uploading
    case finished(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .rendering, .uploading: true
        default: false
        }
    }
}

@MainActor
@Observable
final class RecordingStudioModel {
    let sessionURL: URL
    private(set) var session: RecordingSession?
    private(set) var manifest: CaptureManifest?
    private(set) var pointerCapture = PointerCaptureFile()
    private(set) var recordedPressTimes: [TimeInterval] = []
    private(set) var sourceDuration: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var videoSize = CGSize(width: 1920, height: 1080)
    private(set) var hasCameraVideo = false
    private(set) var hasRecordedAudio = false
    private(set) var cameraOffset: TimeInterval = 0
    private(set) var cameraVideoAspect = RecordingCameraLayoutResolver.defaultCameraAspect
    private(set) var isLoaded = false
    private(set) var loadError: String?

    let screenPlayer = AVPlayer()
    let cameraPlayer = AVPlayer()

    var style = RecordingStudioStyle(background: RecordingStudioDefaults.background) {
        didSet {
            if isLoaded, oldValue.background != style.background {
                RecordingStudioDefaults.background = style.background
            }
            if oldValue.camera.isVisible != style.camera.isVisible {
                updateCameraMatteCache()
            }
            if oldValue.camera.beauty != style.camera.beauty {
                updateCameraBeautyPreview()
            }
            var unchangedCamera = oldValue.camera
            unchangedCamera.beauty = style.camera.beauty
            if oldValue.camera.layout != style.camera.layout {
                rebuildCameraLayoutTimeline()
            } else if unchangedCamera != style.camera || oldValue.padding != style.padding
                || oldValue.cornerRadius != style.cornerRadius {
                rebuildMotionTimeline()
            }
            scheduleProjectSave()
        }
    }
    var previewBackground: AnnotationBackgroundStyle?

    func previewBackground(_ background: AnnotationBackgroundStyle, isHovering: Bool) {
        if isHovering {
            previewBackground = background
        } else if previewBackground == background {
            previewBackground = nil
        }
    }

    var appliedStylePresetID: RecordingStudioStylePreset.ID?
    var zoomEnabled = true {
        didSet {
            scheduleProjectSave()
            rebuildPreviewReframe()
        }
    }
    var exportAppearance = RecordingExportAppearance() {
        didSet {
            guard exportAppearance != oldValue else { return }
            if isLoaded, let session {
                do {
                    try RecordingExportAppearanceStore.save(exportAppearance, to: session.directoryURL)
                    session.removeFinalVideos()
                } catch {
                    NSLog("[Upshot] Export appearance save failed: %@", error.localizedDescription)
                }
            }
            rebuildMotionTimeline()
            keystrokeTimeline = KeystrokeCaptionTimeline(events: pointerCapture.keystrokes.filter(exportAppearance.keystrokes.filter.includes))
        }
    }
    var exportDeliveryOptions = RecordingExportDeliveryOptions() {
        didSet {
            guard exportDeliveryOptions != oldValue else { return }
            if isLoaded, let session {
                do {
                    try RecordingExportOptionStore.save(exportDeliveryOptions, to: session.directoryURL)
                    session.removeFinalVideos()
                } catch {
                    NSLog("[Upshot] Export options save failed: %@", error.localizedDescription)
                }
            }
        }
    }
    var exportSettings = VideoCompressionSettings() {
        didSet { scheduleProjectSave() }
    }
    var showsClickEffects = true {
        didSet { scheduleProjectSave() }
    }
    var showsKeystrokes = true {
        didSet { scheduleProjectSave() }
    }
    var keystrokePlacement: RecordingKeystrokePlacement = .bottomCenter {
        didSet { scheduleProjectSave() }
    }
    var showsSpeedBadge = false {
        didSet { scheduleProjectSave() }
    }
    var speedBadgePlacement: RecordingKeystrokePlacement = .topRight {
        didSet { scheduleProjectSave() }
    }
    var showsSubtitles = true {
        didSet { scheduleProjectSave() }
    }
    var subtitleStyle = SubtitleBarStyle() {
        didSet { scheduleProjectSave() }
    }
    var exportAspect: ExportAspectPreset = .original {
        didSet {
            scheduleProjectSave()
            rebuildPreviewReframe()
        }
    }
    var exportAspectMode: ExportAspectContentMode = .fill {
        didSet {
            scheduleProjectSave()
            rebuildPreviewReframe()
        }
    }
    var videoCropRect = CropGeometry.unit {
        didSet {
            scheduleProjectSave()
            if oldValue != videoCropRect { rebuildMotionTimeline() }
        }
    }
    private(set) var isCroppingVideo = false
    var workingVideoCropRect = CropGeometry.unit
    private(set) var videoCropDrag: CropDrag?
    var videoCropAspect: CropAspectRatio = .freeform
    private(set) var previewReframe: ReframeTrack?
    private(set) var motionTimeline = RecordingStudioMotionTimeline.none
    private var reframeFocusTimeline: PointerTimeline?
    private var reframeFocusResolved = false
    private(set) var subtitleCues: [RecordingSubtitleCue] = []
    private(set) var subtitleTimeline = SubtitleTimeline.empty
    private(set) var transcriptWords: [RecordingTranscriptWord] = []
    private(set) var karaokeTimeline = KaraokeTimeline.empty
    private(set) var activeTranscriptWordIndex: Int?
    var transcriptionState = RecordingTranscriptionState.idle
    private(set) var zoomCues: [ZoomCue] = []
    private(set) var viewportTimeline = ViewportTimeline.identity
    private(set) var pointerTimeline = PointerTimeline.empty
    private(set) var keystrokeTimeline = KeystrokeCaptionTimeline.empty
    var selectedCueID: UUID?
    private(set) var cameraLayoutCues: [RecordingCameraLayoutCue] = []
    private(set) var cameraLayoutTimeline = RecordingCameraLayoutTimeline.constant(RecordingCameraLayout())
    var selectedLayoutCueID: UUID?
    private(set) var textOverlays: [RecordingTextOverlay] = []
    var selectedTextID: UUID?
    private(set) var redactions: [RecordingRedaction] = []
    var selectedRedactionID: UUID?
    let redactionPreview = RecordingRedactionPreviewSource()
    let cameraBeautyPreview = StudioCameraBeautyPreviewSource()
    private(set) var imageOverlays: [RecordingImageOverlay] = []
    var selectedImageID: UUID?
    private(set) var audioClips: [RecordingAudioClip] = []
    var selectedAudioClipID: UUID?
    let overlayImages = RecordingOverlayImageStore()
    private(set) var overlayImageRevision = 0
    private(set) var audioPeaks: [String: [Float]] = [:]
    var mediaImportError: String?
    private(set) var clipTimeline = RecordingClipTimeline(segments: []) {
        didSet {
            if clipTimeline != oldValue {
                speedBadgeTimeline = SpeedBadgeTimeline(clipTimeline: clipTimeline)
            }
        }
    }
    private(set) var speedBadgeTimeline = SpeedBadgeTimeline.empty
    var selectedClipID: UUID?
    var timelineHoverTime: TimeInterval?
    let timelineThumbnails = RecordingTimelineThumbnailStore()

    private(set) var isPlaying = false
    var currentTime: TimeInterval = 0
    var hoverPreviewTime: TimeInterval? {
        didSet {
            guard isLoaded, duration > 0, !isPlaying else { return }
            movePlayers(to: hoverPreviewTime ?? currentTime)
        }
    }
    var exportState: RecordingStudioExportState = .idle {
        didSet { updateCameraMatteCache() }
    }
    var audioExportState: RecordingStudioExportState = .idle
    var shareState: RecordingStudioShareState = .idle {
        didSet { updateCameraMatteCache() }
    }
    private var cameraMatteTask: Task<Void, Never>?
    private(set) var shareItemID: UUID?

    var audioVolume: CGFloat = 1 {
        didSet {
            updatePlaybackVolume()
            scheduleProjectSave()
        }
    }

    private func updatePlaybackVolume() {
        guard let item = screenPlayer.currentItem else { return }
        let clipTrackIDs = Set(playbackClipTrackIDs.values)
        let recordingTracks = item.asset.tracks(withMediaType: .audio).filter { !clipTrackIDs.contains($0.trackID) }
        item.audioMix = RecordingAudioClipMixer.mix(
            recordingTracks: recordingTracks,
            recordingVolume: Double(audioVolume),
            clips: audioClips,
            trackIDs: playbackClipTrackIDs
        )
    }

    var audioExportFormat: RecordingAudioFormat = .m4a {
        didSet { scheduleProjectSave() }
    }
    private(set) var replacementAudio: RecordingReplacementAudio?
    private(set) var replacementAudioError: String?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var exportTask: Task<Void, Never>?
    private var audioExportTask: Task<Void, Never>?
    private var replacementAudioTask: Task<Void, Never>?
    private var screenVideoTrack: AVAssetTrack?
    private var shareTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var projectSaveTask: Task<Void, Never>?
    private var screenAsset: AVURLAsset?
    private var isTornDown = false
    private var isLoading = false
    private var wallpaperCacheLease: BoundedCGImageCache.Lease?
    private let editUndoManager = UndoManager()
    private(set) var undoRevision = 0
    private var zoomEditSnapshot: [ZoomCue]?
    private var viewportRebuildTask: Task<Void, Never>?
    private var layoutEditSnapshot: [RecordingCameraLayoutCue]?
    private var textEditSnapshot: [RecordingTextOverlay]?
    private var redactionEditSnapshot: [RecordingRedaction]?
    private var redactionRefreshTask: Task<Void, Never>?
    private var cameraBeautyRefreshTask: Task<Void, Never>?
    private var textCoalesceTask: Task<Void, Never>?
    private var redactionCoalesceTask: Task<Void, Never>?
    private var imageEditSnapshot: [RecordingImageOverlay]?
    private var audioEditSnapshot: [RecordingAudioClip]?
    private var imageCoalesceTask: Task<Void, Never>?
    private var audioCoalesceTask: Task<Void, Never>?
    private var audioTracksByFile: [String: RecordingAudioFileTrack] = [:]
    private var playbackClipTrackIDs: [UUID: CMPersistentTrackID] = [:]
    private var audioPlaybackRebuildTask: Task<Void, Never>?
    private var mediaLoadTask: Task<Void, Never>?
    private var lastSavedDocument: RecordingEditDocument?
    private var isApplyingDocument = false
    var isAgentSession = false
    private(set) var hasUnsavedChanges = false
    private(set) var saveFlash = false

    init(url: URL) {
        sessionURL = url
        if RecordingSession.isSessionDirectory(url) {
            session = RecordingSession(directoryURL: url)
            exportDeliveryOptions = RecordingExportOptionStore.load(from: url) ?? UpshotPreferences.recordingExtendedExportDefaults
            exportAppearance = RecordingExportAppearanceStore.load(from: url) ?? RecordingExportAppearance()
        } else {
            session = nil
        }
    }

    var screenURL: URL {
        session?.screenURL ?? sessionURL
    }

    var isProject: Bool { session != nil }

    var projectDisplayName: String {
        session?.displayName ?? sessionURL.deletingPathExtension().lastPathComponent
    }

    func load() async {
        guard !isLoaded, !isLoading, !isTornDown, !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        wallpaperCacheLease = AnnotationBackgroundRenderer.beginWallpaperUse()

        if let session {
            manifest = session.loadCaptureManifest()
            pointerCapture = session.loadPointerCapture() ?? PointerCaptureFile()
        }

        let asset = AVURLAsset(url: screenURL)
        screenAsset = asset
        do {
            let (durationTime, tracks) = try await asset.load(.duration, .tracks)
            guard !isTornDown, !Task.isCancelled else { return }
            sourceDuration = durationTime.seconds
            duration = sourceDuration
            if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
                screenVideoTrack = videoTrack
                let naturalSize = try await videoTrack.load(.naturalSize)
                guard !isTornDown, !Task.isCancelled else { return }
                if naturalSize.width > 0, naturalSize.height > 0 {
                    videoSize = naturalSize
                }
            }
            hasRecordedAudio = tracks.contains { $0.mediaType == .audio }
        } catch {
            guard !isTornDown, !Task.isCancelled else { return }
            loadError = "Could not open the recording: \(error.localizedDescription)"
            return
        }

        if session != nil {
            let pointScale = max(manifest?.pixelScale ?? 1, 1)
            let stream = PointerStreamSanitizer.sanitize(
                pointerCapture,
                options: PointerSanitizeOptions(
                    recordingSizeInPoints: CGSize(
                        width: videoSize.width / CGFloat(pointScale),
                        height: videoSize.height / CGFloat(pointScale)
                    )
                )
            )
            pointerCapture = stream.sanitizedCapture
            recordedPressTimes = pointerCapture.presses
                .filter { $0.phase == .down }
                .map(\.time)
            keystrokeTimeline = KeystrokeCaptionTimeline(events: pointerCapture.keystrokes.filter(exportAppearance.keystrokes.filter.includes))
        }

        if let session, session.hasCamera {
            hasCameraVideo = true
            cameraOffset = manifest?.cameraLeadIn ?? 0
            if let aspect = await RecordingCameraVideo.aspect(of: session.cameraURL) {
                guard !isTornDown, !Task.isCancelled else { return }
                cameraVideoAspect = aspect
            }
            StudioCameraMatteGenerator.prewarm()
            cameraPlayer.replaceCurrentItem(with: AVPlayerItem(url: session.cameraURL))
            cameraPlayer.actionAtItemEnd = .pause
            cameraPlayer.isMuted = true
            updateCameraBeautyPreview()
        } else {
            style.camera.isVisible = false
        }

        lastSavedDocument = session?.loadEditDocument()
        let document = session?.effectiveEditDocument()
        showsClickEffects = manifest?.pressEffectsEnabled ?? true
        exportSettings = RecordingExportPreferences.lastSettings
        if let document {
            applyDocumentSettings(document)
        } else if session == nil {
            style = RecordingStudioStyle(
                background: .none,
                padding: 0,
                cornerRadius: 0,
                shadow: 0,
                camera: RecordingCameraBubbleSettings(isVisible: false)
            )
            zoomEnabled = false
        } else {
            zoomCues = ZoomCueSynthesizer.cues(from: pointerCapture, duration: sourceDuration)
            if let defaultPreset = RecordingStudioStylePresetStore.shared.activePreset {
                style = defaultPreset.value
                appliedStylePresetID = defaultPreset.id
            }
        }

        if let storedClips = document?.clips, !storedClips.isEmpty {
            clipTimeline = RecordingClipTimeline(segments: storedClips)
                .normalized(to: sourceDuration)
        } else {
            clipTimeline = .legacyTrim(
                start: document?.trimStart,
                end: document?.trimEnd,
                sourceDuration: sourceDuration
            )
        }
        duration = clipTimeline.duration
        selectedClipID = nil

        if let session, let fileName = document?.replacementAudioFileName {
            let url = session.directoryURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                let loadedAudio = await RecordingReplacementAudio.load(
                    url: url,
                    displayName: document?.replacementAudioDisplayName ?? fileName
                )
                guard !isTornDown, !Task.isCancelled else { return }
                replacementAudio = loadedAudio
            }
        }

        do {
            try rebuildScreenPlayerItem(preserving: 0)
        } catch {
            loadError = "Could not prepare the recording timeline: \(error.localizedDescription)"
            return
        }
        rebuildPointerTimeline()
        rebuildViewportTimeline()
        installObservers()
        isLoaded = true
        updateCameraMatteCache()
        rebuildPreviewReframe()
        loadTimelineThumbnails()

        if let session {
            if session.hasUnsavedDraft {
                hasUnsavedChanges = true
            } else if lastSavedDocument == nil {
                hasUnsavedChanges = true
            } else {
                hasUnsavedChanges = false
                lastSavedDocument = currentDocument()
            }
            session.updateProjectMetadata { $0.lastOpenedAt = Date() }
        }
        StudioProjectRegistry.shared.register(self)
    }

    private func applyDocumentSettings(_ document: RecordingEditDocument) {
        isApplyingDocument = true
        defer { isApplyingDocument = false }

        style = document.style.value
        zoomEnabled = document.zoomEnabled
        zoomCues = document.zoomCues
        cameraLayoutCues = (document.cameraLayoutCues ?? []).sorted { $0.start < $1.start }
        textOverlays = document.textOverlays ?? []
        redactions = document.redactions ?? []
        imageOverlays = document.imageOverlays ?? []
        audioClips = document.audioClips ?? []
        loadOverlayMedia()
        redactionPreview.update(redactions: redactions, clipTimeline: clipTimeline)
        exportSettings = document.exportSettings ?? RecordingExportPreferences.lastSettings
        if document.exportSettings == nil {
            exportSettings.frameRate = nil
            exportSettings.motionBlurEnabled = nil
        }
        showsClickEffects = document.showsClickEffects ?? showsClickEffects
        showsKeystrokes = document.showsKeystrokes ?? true
        keystrokePlacement = document.keystrokePlacement ?? .bottomCenter
        showsSpeedBadge = document.showsSpeedBadge ?? false
        speedBadgePlacement = document.speedBadgePlacement ?? .topRight
        showsSubtitles = document.showsSubtitles ?? true
        subtitleCues = document.subtitleCues ?? []
        subtitleTimeline = SubtitleTimeline(cues: subtitleCues)
        transcriptWords = document.subtitleWords ?? []
        karaokeTimeline = KaraokeTimeline(cues: subtitleCues, words: transcriptWords)
        subtitleStyle = document.subtitleStyle
        exportAspect = document.exportAspectPreset
        exportAspectMode = document.exportAspectContentMode
        videoCropRect = document.normalizedVideoCropRect
        audioExportFormat = document.audioExportFormatValue
        audioVolume = CGFloat(RecordingAudioGain.normalized(document.audioVolume ?? 1))
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        if isLoaded { writeDraftNow() }
        isLoaded = false
        StudioProjectRegistry.shared.unregister(self)
        exportTask?.cancel()
        audioExportTask?.cancel()
        replacementAudioTask?.cancel()
        cancelShare()
        transcriptionTask?.cancel()
        projectSaveTask?.cancel()
        cameraMatteTask?.cancel()
        cameraMatteTask = nil
        exportTask = nil
        audioExportTask = nil
        replacementAudioTask = nil
        shareTask = nil
        transcriptionTask = nil
        projectSaveTask = nil
        timelineThumbnails.releaseResources()
        pause()
        if let timeObserver {
            screenPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        screenPlayer.replaceCurrentItem(with: nil)
        cameraPlayer.replaceCurrentItem(with: nil)
        screenAsset?.cancelLoading()
        screenAsset = nil
        screenVideoTrack = nil
        replacementAudio = nil
        editUndoManager.removeAllActions()
        zoomEditSnapshot = nil
        viewportRebuildTask?.cancel()
        viewportRebuildTask = nil
        layoutEditSnapshot = nil
        textEditSnapshot = nil
        redactionEditSnapshot = nil
        redactionRefreshTask?.cancel()
        redactionRefreshTask = nil
        cameraBeautyRefreshTask?.cancel()
        cameraBeautyRefreshTask = nil
        textCoalesceTask?.cancel()
        redactionCoalesceTask?.cancel()
        imageCoalesceTask?.cancel()
        audioCoalesceTask?.cancel()
        audioPlaybackRebuildTask?.cancel()
        mediaLoadTask?.cancel()
        imageEditSnapshot = nil
        audioEditSnapshot = nil
        lastSavedDocument = nil
        pointerCapture = PointerCaptureFile()
        pointerTimeline = .empty
        keystrokeTimeline = .empty
        viewportTimeline = .identity
        previewReframe = nil
        reframeFocusTimeline = nil
        recordedPressTimes.removeAll()
        zoomCues.removeAll()
        cameraLayoutCues.removeAll()
        textOverlays.removeAll()
        redactions.removeAll()
        imageOverlays.removeAll()
        audioClips.removeAll()
        audioTracksByFile.removeAll()
        overlayImages.removeAll()
        subtitleCues.removeAll()
        transcriptWords.removeAll()
        subtitleTimeline = .empty
        karaokeTimeline = .empty
        clipTimeline = RecordingClipTimeline(segments: [])
        wallpaperCacheLease = nil
    }


    func applyStylePreset(_ preset: RecordingStudioStylePreset) {
        style = preset.value
        appliedStylePresetID = preset.id
    }


    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !isPlaying else { return }
        if hoverPreviewTime != nil {
            hoverPreviewTime = nil
        }
        guard duration >= RecordingClipSegment.minimumDuration else { return }
        if currentTime < 0 || currentTime >= duration - 0.05 {
            seek(to: 0)
        }
        isPlaying = true
        screenPlayer.play()
        syncCameraPlayback()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        screenPlayer.pause()
        cameraPlayer.pause()
    }

    func seek(to time: TimeInterval) {
        let clamped = min(max(time, 0), max(duration, 0))
        currentTime = clamped
        updateActiveTranscriptWord()
        movePlayers(to: clamped)
        if isPlaying {
            syncCameraPlayback()
        }
    }

    private func movePlayers(to time: TimeInterval) {
        let editorTime = min(max(time, 0), max(duration, 0))
        let sourceTime = clipTimeline.sourceTime(at: editorTime)
        let target = CMTime(seconds: editorTime, preferredTimescale: 600)
        screenPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if hasCameraVideo {
            if sourceTime >= cameraOffset {
                let cameraTime = CMTime(seconds: max(0, sourceTime - cameraOffset), preferredTimescale: 600)
                cameraPlayer.seek(to: cameraTime, toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                cameraPlayer.pause()
                cameraPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    var displayTime: TimeInterval {
        if isPlaying {
            let time = screenPlayer.currentTime().seconds
            return time.isFinite ? time : currentTime
        }
        return hoverPreviewTime ?? currentTime
    }

    private func installObservers() {
        timeObserver = screenPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.02, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isPlaying {
                    let seconds = time.seconds
                    if seconds >= self.duration - 0.001 {
                        self.pause()
                        self.currentTime = self.duration
                        self.screenPlayer.seek(
                            to: CMTime(seconds: self.duration, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        return
                    }
                    self.currentTime = seconds
                    self.updateActiveTranscriptWord()
                    self.correctCameraDriftIfNeeded()
                }
            }
        }

        installEndObserver()
    }

    private func installEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: screenPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isPlaying = false
                self.cameraPlayer.pause()
                self.currentTime = self.duration
            }
        }
    }


    var canUndo: Bool {
        _ = undoRevision
        return editUndoManager.canUndo
    }

    var canRedo: Bool {
        _ = undoRevision
        return editUndoManager.canRedo
    }

    var selectedClip: RecordingClipSegment? {
        guard let selectedClipID else { return nil }
        return clipTimeline.segments.first { $0.id == selectedClipID }
    }

    var hasClipEdits: Bool {
        !clipTimeline.isUnedited(sourceDuration: sourceDuration)
    }

    var canDeleteSelectedClip: Bool {
        selectedClipID != nil && clipTimeline.segments.count > 1
    }

    func selectClip(id: UUID) {
        guard clipTimeline.segments.contains(where: { $0.id == id }) else { return }
        clearTimelineSelection()
        selectedClipID = id
    }

    func selectZoomCue(id: UUID) {
        guard zoomCues.contains(where: { $0.id == id }) else { return }
        clearTimelineSelection()
        selectedCueID = id
    }

    func selectLayoutCue(id: UUID) {
        guard cameraLayoutCues.contains(where: { $0.id == id }) else { return }
        clearTimelineSelection()
        selectedLayoutCueID = id
    }

    func clearTimelineSelection() {
        selectedCueID = nil
        selectedClipID = nil
        selectedLayoutCueID = nil
        selectedTextID = nil
        selectedRedactionID = nil
        selectedImageID = nil
        selectedAudioClipID = nil
    }

    func undo() {
        guard editUndoManager.canUndo else { return }
        pause()
        editUndoManager.undo()
        undoRevision &+= 1
    }

    func redo() {
        guard editUndoManager.canRedo else { return }
        pause()
        editUndoManager.redo()
        undoRevision &+= 1
    }

    func splitClip(at editorTime: TimeInterval) {
        guard let result = clipTimeline.split(at: editorTime) else { return }
        applyClipTimeline(
            result.timeline,
            selectedID: result.selectedID,
            playheadTime: min(max(editorTime, 0), duration),
            actionName: "Split Clip"
        )
    }

    func splitClipAtHover() {
        guard let timelineHoverTime else { return }
        splitClip(at: timelineHoverTime)
    }

    func deleteSelectedClip() {
        guard let selectedClipID,
              let deletedRange = clipTimeline.editorRange(for: selectedClipID),
              let next = clipTimeline.deleting(segmentID: selectedClipID) else {
            return
        }
        let seekTime = min(deletedRange.lowerBound, next.duration)
        let nextSelection = next.location(at: seekTime)?.segmentID
            ?? next.segments.last?.id
        applyClipTimeline(
            next,
            selectedID: nextSelection,
            playheadTime: seekTime,
            actionName: "Delete Clip"
        )
    }

    func trimClip(_ replacement: RecordingClipSegment) {
        let next = clipTimeline.replacing(replacement)
        guard next != clipTimeline else { return }
        let editorTime = next.editorRange(for: replacement.id)?.lowerBound ?? currentTime
        applyClipTimeline(
            next,
            selectedID: replacement.id,
            playheadTime: min(currentTime, next.duration),
            actionName: "Trim Clip",
            hoverTime: editorTime
        )
    }

    func setClipSpeed(_ speed: Double, forClipID id: UUID) {
        guard let segment = clipTimeline.segments.first(where: { $0.id == id }) else { return }
        let clamped = min(max(speed, RecordingClipSegment.minimumSpeed), RecordingClipSegment.maximumSpeed)
        guard abs(segment.speed - clamped) > 0.000_001 else { return }
        var replacement = segment
        replacement.speed = clamped
        let next = clipTimeline.replacing(replacement)
        applyClipTimeline(
            next,
            selectedID: id,
            playheadTime: min(currentTime, next.duration),
            actionName: "Change Clip Speed"
        )
    }

    func resetClips() {
        let full = RecordingClipTimeline.full(sourceDuration: sourceDuration)
        guard full != clipTimeline else { return }
        applyClipTimeline(
            full,
            selectedID: full.segments.first?.id,
            playheadTime: 0,
            actionName: "Reset Clips"
        )
    }

    private func applyClipTimeline(
        _ requestedTimeline: RecordingClipTimeline,
        selectedID: UUID?,
        playheadTime: TimeInterval,
        actionName: String,
        hoverTime: TimeInterval? = nil
    ) {
        let next = requestedTimeline.normalized(to: sourceDuration)
        guard !next.segments.isEmpty, next != clipTimeline else { return }

        let previousTimeline = clipTimeline
        let previousSelection = selectedClipID
        let previousTime = currentTime
        registerUndo(actionName) { target in
            target.applyClipTimeline(
                previousTimeline,
                selectedID: previousSelection,
                playheadTime: previousTime,
                actionName: actionName
            )
        }

        pause()
        hoverPreviewTime = nil
        timelineHoverTime = nil
        clipTimeline = next
        duration = next.duration
        selectedClipID = selectedID.flatMap { id in
            next.segments.contains(where: { $0.id == id }) ? id : nil
        } ?? next.segments.first?.id
        rebuildPointerTimeline()
        rebuildViewportTimeline()

        do {
            try rebuildScreenPlayerItem(preserving: min(max(playheadTime, 0), duration))
            if let hoverTime {
                hoverPreviewTime = min(max(hoverTime, 0), duration)
            }
        } catch {
            loadError = "Could not update the recording timeline: \(error.localizedDescription)"
        }
        updateActiveTranscriptWord()
        scheduleProjectSave()
    }

    private func rebuildScreenPlayerItem(preserving editorTime: TimeInterval) throws {
        guard let screenAsset else { return }
        let playbackAsset: AVAsset
        if let replacementAudio, let screenVideoTrack {
            playbackAsset = try RecordingCompositionBuilder.makeAsset(
                videoTrack: screenVideoTrack,
                timeline: clipTimeline,
                sourceDuration: sourceDuration,
                replacementAudio: replacementAudio
            )
        } else {
            playbackAsset = try RecordingCompositionBuilder.makeAsset(
                from: screenAsset,
                timeline: clipTimeline,
                sourceDuration: sourceDuration
            )
        }

        let composedAsset = try addingAudioClips(to: playbackAsset)
        let item = AVPlayerItem(asset: composedAsset)
        redactionPreview.update(redactions: redactions, clipTimeline: clipTimeline)
        if !redactions.isEmpty {
            item.videoComposition = redactionPreview.makeVideoComposition(for: composedAsset)
        }
        screenPlayer.replaceCurrentItem(with: item)
        updatePlaybackVolume()
        screenPlayer.actionAtItemEnd = .pause
        currentTime = min(max(editorTime, 0), duration)
        movePlayers(to: currentTime)
        if timeObserver != nil {
            installEndObserver()
        }
    }

    private func registerUndo(
        _ actionName: String,
        operation: @escaping @MainActor (RecordingStudioModel) -> Void
    ) {
        editUndoManager.registerUndo(withTarget: self) { target in
            operation(target)
        }
        editUndoManager.setActionName(actionName)
        undoRevision &+= 1
    }

    private func loadTimelineThumbnails() {
        timelineThumbnails.prepare(url: screenURL, duration: sourceDuration)
    }

    private func speed(atEditorTime time: TimeInterval) -> Double {
        guard let location = clipTimeline.location(at: time) else { return 1 }
        return clipTimeline.segments[location.segmentIndex].speed
    }

    private func syncCameraPlayback() {
        guard hasCameraVideo else { return }
        let sourceTime = clipTimeline.sourceTime(at: currentTime)
        guard sourceTime >= cameraOffset else {
            cameraPlayer.pause()
            cameraPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        let rate = Float(speed(atEditorTime: currentTime))
        let cameraTime = CMTime(seconds: max(0, sourceTime - cameraOffset), preferredTimescale: 600)
        cameraPlayer.seek(to: cameraTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.cameraPlayer.rate = rate
            }
        }
    }

    private func correctCameraDriftIfNeeded() {
        guard hasCameraVideo, isPlaying else { return }
        let sourceTime = clipTimeline.sourceTime(at: currentTime)
        guard sourceTime >= cameraOffset else {
            cameraPlayer.pause()
            return
        }
        if cameraPlayer.rate == 0 {
            syncCameraPlayback()
            return
        }
        let targetRate = Float(speed(atEditorTime: currentTime))
        if abs(cameraPlayer.rate - targetRate) > 0.01 {
            cameraPlayer.rate = targetRate
        }
        let expected = sourceTime - cameraOffset
        let actual = cameraPlayer.currentTime().seconds
        guard expected.isFinite, actual.isFinite else { return }
        if abs(expected - actual) > 0.12 {
            cameraPlayer.seek(
                to: CMTime(seconds: max(0, expected), preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }


    private func replaceZoomCues(_ cues: [ZoomCue]) {
        zoomCues = cues.sorted { $0.start < $1.start }
        if zoomEditSnapshot != nil {
            scheduleViewportRebuild()
        } else {
            rebuildViewportTimeline()
        }
        scheduleProjectSave()
    }

    private func applyZoomCues(_ cues: [ZoomCue], actionName: String) {
        let sorted = cues.sorted { $0.start < $1.start }
        guard sorted != zoomCues else { return }
        let previous = zoomCues
        registerUndo(actionName) { target in
            target.applyZoomCues(previous, actionName: actionName)
        }
        replaceZoomCues(sorted)
    }

    func beginZoomCueEdit() {
        if zoomEditSnapshot == nil {
            zoomEditSnapshot = zoomCues
        }
    }

    func endZoomCueEdit(actionName: String = "Edit Zoom") {
        guard let previous = zoomEditSnapshot else { return }
        zoomEditSnapshot = nil
        if viewportRebuildTask != nil {
            viewportRebuildTask?.cancel()
            viewportRebuildTask = nil
            rebuildViewportTimeline()
        }
        guard previous != zoomCues else { return }
        registerUndo(actionName) { target in
            target.applyZoomCues(previous, actionName: actionName)
        }
    }

    func resynthesizeZoomCues() {
        applyZoomCues(
            ZoomCueSynthesizer.cues(from: pointerCapture, duration: sourceDuration),
            actionName: "Reset Zooms"
        )
    }

    func addZoomCue(at time: TimeInterval) {
        let sourceTime = clipTimeline.sourceTime(at: time)
        let start = min(max(0, sourceTime), max(0, sourceDuration - 1))
        insertZoomCue(start: start, end: min(sourceDuration, start + 3))
    }

    private func neighborBounds(
        forCueAt index: Int,
        in cues: [ZoomCue]
    ) -> (lower: TimeInterval, upper: TimeInterval) {
        (
            lower: index > 0 ? max(0, cues[index - 1].end) : 0,
            upper: index + 1 < cues.count
                ? min(cues[index + 1].start, sourceDuration)
                : sourceDuration
        )
    }

    private func freeSpan(
        from start: TimeInterval,
        preferredEnd: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard sourceDuration > 0 else { return nil }
        let length = max(preferredEnd - start, ZoomCue.minimumDuration)
        var lower = min(max(start, 0), sourceDuration)
        while let covering = zoomCues.first(where: { $0.start <= lower && $0.end > lower }) {
            lower = covering.end
        }
        let upper = zoomCues
            .filter { $0.start > lower }
            .map(\.start)
            .min() ?? sourceDuration
        guard upper - lower >= ZoomCue.minimumDuration else { return nil }
        return lower...min(lower + length, upper)
    }

    func addZoomCue(overEditorRange range: ClosedRange<TimeInterval>) {
        guard let span = drawnSourceSpan(
            for: range,
            among: zoomCues.map { $0.start...$0.end },
            minimum: ZoomCue.minimumDuration
        ) else { return }
        appendZoomCue(span)
    }

    private func insertZoomCue(start: TimeInterval, end: TimeInterval) {
        guard let span = freeSpan(from: start, preferredEnd: end) else { return }
        appendZoomCue(span)
    }

    private func appendZoomCue(_ span: ClosedRange<TimeInterval>) {
        let hasPointerTrack = !pointerCapture.travel.isEmpty || !pointerCapture.presses.isEmpty
        let editorTime = clipTimeline.editorTime(forSourceTime: span.lowerBound) ?? currentTime
        let target = pointerTimeline.location(at: editorTime) ?? CGPoint(x: 0.5, y: 0.5)
        let cue = ZoomCue(
            start: span.lowerBound,
            end: span.upperBound,
            zoom: 1.5,
            anchorMode: hasPointerTrack ? .pointerAnchor : .pinnedAnchor,
            pinnedPoint: target,
            boundsBias: hasPointerTrack ? 0.25 : 0
        )
        var cues = zoomCues
        cues.append(cue)
        applyZoomCues(cues, actionName: "Add Zoom")
        clearTimelineSelection()
        selectedCueID = cue.id
    }

    func removeZoomCue(id: UUID) {
        applyZoomCues(zoomCues.filter { $0.id != id }, actionName: "Remove Zoom")
        if selectedCueID == id {
            selectedCueID = nil
        }
    }

    func updateZoomCue(_ cue: ZoomCue) {
        var cues = zoomCues
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        let bounds = neighborBounds(forCueAt: index, in: cues)
        var updated = sanitized(cue)
        updated.start = min(
            max(updated.start, bounds.lower),
            max(bounds.lower, bounds.upper - ZoomCue.minimumDuration)
        )
        updated.end = min(
            max(updated.end, updated.start + ZoomCue.minimumDuration),
            bounds.upper
        )
        cues[index] = updated
        replaceZoomCues(cues)
    }

    func moveZoomCue(_ cue: ZoomCue) {
        var cues = zoomCues
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        let bounds = neighborBounds(forCueAt: index, in: cues)
        let room = max(bounds.upper - bounds.lower, ZoomCue.minimumDuration)
        let length = min(max(cue.duration, ZoomCue.minimumDuration), room)
        var moved = sanitized(cue)
        moved.start = min(max(cue.start, bounds.lower), max(bounds.lower, bounds.upper - length))
        moved.end = min(moved.start + length, bounds.upper)
        cues[index] = moved
        replaceZoomCues(cues)
    }

    private func sanitized(_ cue: ZoomCue) -> ZoomCue {
        var cue = cue
        cue.start = min(max(0, cue.start), sourceDuration)
        cue.end = min(max(cue.start, cue.end), sourceDuration)
        cue.zoom = min(max(cue.zoom, 1), 4)
        cue.boundsBias = min(max(cue.boundsBias, 0), 1)
        cue.pinnedPoint = CGPoint(
            x: min(max(cue.pinnedPoint.x, 0), 1),
            y: min(max(cue.pinnedPoint.y, 0), 1)
        )
        return cue
    }

    var selectedCue: ZoomCue? {
        zoomCues.first { $0.id == selectedCueID }
    }


    var selectedLayoutCue: RecordingCameraLayoutCue? {
        cameraLayoutCues.first { $0.id == selectedLayoutCueID }
    }

    var cameraLayoutTimelineBlocks: [RecordingCameraLayoutTimelineBlock] {
        RecordingCameraLayoutTimeline.blocks(for: cameraLayoutCues, clipTimeline: clipTimeline)
    }

    func layoutCue(atEditorTime time: TimeInterval) -> RecordingCameraLayoutCue? {
        cameraLayoutTimelineBlocks
            .first { $0.editorStart <= time && time < $0.editorEnd }?
            .cue
    }

    func editLayout(atEditorTime time: TimeInterval, actionName: String, _ change: (inout RecordingCameraLayout) -> Void) {
        if var cue = layoutCue(atEditorTime: time) {
            change(&cue.layout)
            updateLayoutCue(cue, actionName: actionName)
        } else {
            change(&style.camera.layout)
        }
    }

    private func rebuildCameraLayoutTimeline(rebuildsZoom: Bool = true) {
        let next = RecordingCameraLayoutTimeline.build(
            defaultLayout: style.camera.layout,
            cues: cameraLayoutCues,
            clipTimeline: clipTimeline
        )
        if next != cameraLayoutTimeline {
            cameraLayoutTimeline = next
            updateCameraMatteCache()
        }
        if rebuildsZoom { rebuildMotionTimeline() }
    }

    private func updateCameraMatteCache() {
        let isRendering = exportState.isExporting || shareState.isBusy
        guard isLoaded, !isTornDown, !isRendering, showsCameraLayer,
              cameraLayoutTimeline.usesCutout, let session,
              !StudioCameraMatteCache.isComplete(forCamera: session.cameraURL)
        else {
            if isRendering || isTornDown {
                cameraMatteTask?.cancel()
                cameraMatteTask = nil
            }
            return
        }
        guard cameraMatteTask == nil else { return }
        let cameraURL = session.cameraURL
        cameraMatteTask = Task(priority: .utility) { [weak self] in
            await StudioCameraMatteCache.generate(cameraURL: cameraURL)
            guard !Task.isCancelled else { return }
            self?.cameraMatteTask = nil
        }
    }

    private func replaceLayoutCues(_ cues: [RecordingCameraLayoutCue]) {
        cameraLayoutCues = cues.sorted { $0.start < $1.start }
        rebuildCameraLayoutTimeline()
        scheduleProjectSave()
    }

    private func applyLayoutCues(_ cues: [RecordingCameraLayoutCue], actionName: String) {
        let sorted = cues.sorted { $0.start < $1.start }
        guard sorted != cameraLayoutCues else { return }
        let previous = cameraLayoutCues
        registerUndo(actionName) { target in
            target.applyLayoutCues(previous, actionName: actionName)
        }
        replaceLayoutCues(sorted)
    }

    func beginLayoutCueEdit() {
        if layoutEditSnapshot == nil {
            layoutEditSnapshot = cameraLayoutCues
        }
    }

    func endLayoutCueEdit(actionName: String = "Edit Layout") {
        guard let previous = layoutEditSnapshot else { return }
        layoutEditSnapshot = nil
        guard previous != cameraLayoutCues else { return }
        registerUndo(actionName) { target in
            target.applyLayoutCues(previous, actionName: actionName)
        }
    }

    func addLayoutCue(at time: TimeInterval, layout: RecordingCameraLayout? = nil) {
        let sourceTime = clipTimeline.sourceTime(at: time)
        let start = min(max(0, sourceTime), max(0, sourceDuration - RecordingCameraLayoutCue.minimumDuration))
        insertLayoutCue(start: start, end: min(sourceDuration, start + 3), layout: layout)
    }

    func addLayoutCue(overEditorRange range: ClosedRange<TimeInterval>) {
        guard let span = drawnSourceSpan(
            for: range,
            among: cameraLayoutCues.map { $0.start...$0.end },
            minimum: RecordingCameraLayoutCue.minimumDuration
        ) else { return }
        appendLayoutCue(span, layout: nil)
    }

    private func insertLayoutCue(start: TimeInterval, end: TimeInterval, layout: RecordingCameraLayout?) {
        guard let span = freeLayoutSpan(from: start, preferredEnd: end) else { return }
        appendLayoutCue(span, layout: layout)
    }

    private func appendLayoutCue(_ span: ClosedRange<TimeInterval>, layout: RecordingCameraLayout?) {
        let cue = RecordingCameraLayoutCue(
            start: span.lowerBound,
            end: span.upperBound,
            layout: layout ?? .suggestedCue(over: style.camera.layout)
        )
        var cues = cameraLayoutCues
        cues.append(cue)
        applyLayoutCues(cues, actionName: "Add Layout")
        selectLayoutCue(id: cue.id)
    }

    private func freeLayoutSpan(from start: TimeInterval, preferredEnd: TimeInterval) -> ClosedRange<TimeInterval>? {
        guard sourceDuration > 0 else { return nil }
        let minimum = RecordingCameraLayoutCue.minimumDuration
        let length = max(preferredEnd - start, minimum)
        var lower = min(max(start, 0), sourceDuration)
        while let covering = cameraLayoutCues.first(where: { $0.start <= lower && $0.end > lower }) {
            lower = covering.end
        }
        let upper = cameraLayoutCues
            .filter { $0.start > lower }
            .map(\.start)
            .min() ?? sourceDuration
        guard upper - lower >= minimum else { return nil }
        return lower...min(lower + length, upper)
    }

    private func layoutNeighborBounds(forCueAt index: Int) -> (lower: TimeInterval, upper: TimeInterval) {
        let cues = cameraLayoutCues
        return (
            lower: index > 0 ? max(0, cues[index - 1].end) : 0,
            upper: index + 1 < cues.count ? min(cues[index + 1].start, sourceDuration) : sourceDuration
        )
    }

    func removeLayoutCue(id: UUID) {
        applyLayoutCues(cameraLayoutCues.filter { $0.id != id }, actionName: "Remove Layout")
        if selectedLayoutCueID == id {
            selectedLayoutCueID = nil
        }
    }

    func updateLayoutCue(_ cue: RecordingCameraLayoutCue, actionName: String) {
        beginLayoutCueEdit()
        resizeLayoutCue(cue)
        endLayoutCueEdit(actionName: actionName)
    }

    func resizeLayoutCue(_ cue: RecordingCameraLayoutCue) {
        var cues = cameraLayoutCues
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        let bounds = layoutNeighborBounds(forCueAt: index)
        let minimum = RecordingCameraLayoutCue.minimumDuration
        var updated = cue
        updated.start = min(max(updated.start, bounds.lower), max(bounds.lower, bounds.upper - minimum))
        updated.end = min(max(updated.end, updated.start + minimum), bounds.upper)
        cues[index] = updated
        replaceLayoutCues(cues)
    }

    func moveLayoutCue(_ cue: RecordingCameraLayoutCue) {
        var cues = cameraLayoutCues
        guard let index = cues.firstIndex(where: { $0.id == cue.id }) else { return }
        let bounds = layoutNeighborBounds(forCueAt: index)
        let minimum = RecordingCameraLayoutCue.minimumDuration
        let room = max(bounds.upper - bounds.lower, minimum)
        let length = min(max(cue.duration, minimum), room)
        var moved = cue
        moved.start = min(max(cue.start, bounds.lower), max(bounds.lower, bounds.upper - length))
        moved.end = min(moved.start + length, bounds.upper)
        cues[index] = moved
        replaceLayoutCues(cues)
    }


    var selectedText: RecordingTextOverlay? {
        textOverlays.first { $0.id == selectedTextID }
    }

    var textTimelineBlocks: [RecordingOverlayTimelineBlock<RecordingTextOverlay>] {
        RecordingOverlayTimelineBlock.blocks(for: textOverlays, clipTimeline: clipTimeline) {
            ($0.start, $0.end)
        }
    }

    func texts(atEditorTime time: TimeInterval) -> [RecordingTextOverlay] {
        guard !textOverlays.isEmpty, clipTimeline.location(at: time) != nil else { return [] }
        let sourceTime = clipTimeline.sourceTime(at: time)
        return textOverlays.filter { $0.isActive(atSourceTime: sourceTime) }
    }

    func selectText(id: UUID) {
        guard textOverlays.contains(where: { $0.id == id }) else { return }
        clearTimelineSelection()
        selectedTextID = id
    }

    func addText(atEditorTime time: TimeInterval) {
        let range = sourceRange(startingAt: time, length: RecordingTextOverlay.defaultDuration,
                                minimum: RecordingTextOverlay.minimumDuration)
        guard let range else { return }
        insertText(RecordingTextOverlay(start: range.lowerBound, end: range.upperBound))
    }

    func addText(fromEditorTime editorStart: TimeInterval, toEditorTime editorEnd: TimeInterval) {
        guard let range = sourceRange(fromEditorTime: editorStart, toEditorTime: editorEnd,
                                      minimum: RecordingTextOverlay.minimumDuration) else { return }
        insertText(RecordingTextOverlay(start: range.lowerBound, end: range.upperBound))
    }

    private func insertText(_ overlay: RecordingTextOverlay) {
        applyTexts(textOverlays + [overlay], actionName: "Add Text")
        selectText(id: overlay.id)
    }

    func removeText(id: UUID) {
        applyTexts(textOverlays.filter { $0.id != id }, actionName: "Remove Text")
        if selectedTextID == id { selectedTextID = nil }
    }

    func beginTextEdit() {
        if textEditSnapshot == nil { textEditSnapshot = textOverlays }
    }

    func endTextEdit(actionName: String = "Edit Text") {
        guard let previous = textEditSnapshot else { return }
        textEditSnapshot = nil
        guard previous != textOverlays else { return }
        registerUndo(actionName) { target in
            target.applyTexts(previous, actionName: actionName)
        }
    }

    func setText(_ overlay: RecordingTextOverlay) {
        guard let index = textOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        var texts = textOverlays
        var updated = overlay
        let range = clampedSourceRange(start: overlay.start, end: overlay.end, minimum: RecordingTextOverlay.minimumDuration)
        updated.start = range.lowerBound
        updated.end = range.upperBound
        updated.fontSize = min(max(updated.fontSize, RecordingTextOverlay.fontSizeRange.lowerBound),
                               RecordingTextOverlay.fontSizeRange.upperBound)
        updated.center = CGPoint(x: min(max(updated.center.x, 0), 1), y: min(max(updated.center.y, 0), 1))
        texts[index] = updated
        replaceTexts(texts)
    }

    func editText(_ overlay: RecordingTextOverlay, actionName: String) {
        beginTextEdit()
        setText(overlay)
        textCoalesceTask?.cancel()
        textCoalesceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.endTextEdit(actionName: actionName)
        }
    }

    func updateText(_ overlay: RecordingTextOverlay, actionName: String) {
        beginTextEdit()
        setText(overlay)
        endTextEdit(actionName: actionName)
    }

    private func replaceTexts(_ texts: [RecordingTextOverlay]) {
        textOverlays = texts
        scheduleProjectSave()
    }

    private func applyTexts(_ texts: [RecordingTextOverlay], actionName: String) {
        guard texts != textOverlays else { return }
        let previous = textOverlays
        registerUndo(actionName) { target in
            target.applyTexts(previous, actionName: actionName)
        }
        replaceTexts(texts)
        if let selectedTextID, !texts.contains(where: { $0.id == selectedTextID }) {
            self.selectedTextID = nil
        }
    }


    var selectedRedaction: RecordingRedaction? {
        redactions.first { $0.id == selectedRedactionID }
    }

    var redactionTimelineBlocks: [RecordingOverlayTimelineBlock<RecordingRedaction>] {
        RecordingOverlayTimelineBlock.blocks(for: redactions, clipTimeline: clipTimeline) {
            ($0.start, $0.end)
        }
    }

    func redactions(atEditorTime time: TimeInterval) -> [RecordingRedaction] {
        guard !redactions.isEmpty, clipTimeline.location(at: time) != nil else { return [] }
        let sourceTime = clipTimeline.sourceTime(at: time)
        return redactions.filter { $0.start <= sourceTime && sourceTime < $0.end }
    }

    func selectRedaction(id: UUID) {
        guard redactions.contains(where: { $0.id == id }) else { return }
        clearTimelineSelection()
        selectedRedactionID = id
    }

    func addRedaction(atEditorTime time: TimeInterval, style: RecordingRedaction.Style = .pixelate) {
        guard let range = sourceRange(startingAt: time, length: RecordingRedaction.defaultDuration,
                                      minimum: RecordingRedaction.minimumDuration) else { return }
        var redaction = RecordingRedaction(start: range.lowerBound, end: range.upperBound)
        redaction.style = style
        applyRedactions(redactions + [redaction], actionName: style == .blur ? "Add Blur" : "Add Pixelate")
        selectRedaction(id: redaction.id)
    }

    func removeRedaction(id: UUID) {
        applyRedactions(redactions.filter { $0.id != id }, actionName: "Remove Pixelate")
        if selectedRedactionID == id { selectedRedactionID = nil }
    }

    func beginRedactionEdit() {
        if redactionEditSnapshot == nil { redactionEditSnapshot = redactions }
    }

    func endRedactionEdit(actionName: String = "Edit Pixelate") {
        guard let previous = redactionEditSnapshot else { return }
        redactionEditSnapshot = nil
        guard previous != redactions else { return }
        registerUndo(actionName) { target in
            target.applyRedactions(previous, actionName: actionName)
        }
    }

    func setRedaction(_ redaction: RecordingRedaction) {
        guard let index = redactions.firstIndex(where: { $0.id == redaction.id }) else { return }
        var updated = redaction
        let range = clampedSourceRange(start: redaction.start, end: redaction.end, minimum: RecordingRedaction.minimumDuration)
        updated.start = range.lowerBound
        updated.end = range.upperBound
        updated.rect = RecordingRedaction.clamped(redaction.rect)
        updated.amount = min(max(updated.amount, 0), 1)
        var all = redactions
        all[index] = updated
        replaceRedactions(all)
    }

    func editRedaction(_ redaction: RecordingRedaction, actionName: String) {
        beginRedactionEdit()
        setRedaction(redaction)
        redactionCoalesceTask?.cancel()
        redactionCoalesceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.endRedactionEdit(actionName: actionName)
        }
    }

    func updateRedaction(_ redaction: RecordingRedaction, actionName: String) {
        beginRedactionEdit()
        setRedaction(redaction)
        endRedactionEdit(actionName: actionName)
    }

    private func replaceRedactions(_ all: [RecordingRedaction]) {
        let wasEmpty = redactions.isEmpty
        redactions = all
        redactionPreview.update(redactions: all, clipTimeline: clipTimeline)
        if let item = screenPlayer.currentItem {
            if all.isEmpty {
                item.videoComposition = nil
            } else if wasEmpty {
                item.videoComposition = redactionPreview.makeVideoComposition(for: item.asset)
            }
        }
        scheduleRedactionRefresh()
        scheduleProjectSave()
    }

    private func applyRedactions(_ all: [RecordingRedaction], actionName: String) {
        guard all != redactions else { return }
        let previous = redactions
        registerUndo(actionName) { target in
            target.applyRedactions(previous, actionName: actionName)
        }
        replaceRedactions(all)
        if let selectedRedactionID, !all.contains(where: { $0.id == selectedRedactionID }) {
            self.selectedRedactionID = nil
        }
    }

    private func scheduleRedactionRefresh() {
        guard !isPlaying, redactionRefreshTask == nil else { return }
        redactionRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            self.redactionRefreshTask = nil
            guard !self.isPlaying, let item = self.screenPlayer.currentItem else { return }
            if !self.redactions.isEmpty {
                item.videoComposition = self.redactionPreview.makeVideoComposition(for: item.asset)
            }
            self.movePlayers(to: self.displayTime)
        }
    }

    private func updateCameraBeautyPreview() {
        let beauty = style.camera.beauty
        cameraBeautyPreview.update(beauty)
        guard let item = cameraPlayer.currentItem else { return }
        if !beauty.isActive {
            item.videoComposition = nil
        } else if item.videoComposition == nil {
            item.videoComposition = cameraBeautyPreview.makeVideoComposition(for: item.asset)
        }
        scheduleCameraBeautyRefresh()
    }

    private func scheduleCameraBeautyRefresh() {
        guard !isPlaying, cameraBeautyRefreshTask == nil else { return }
        cameraBeautyRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            self.cameraBeautyRefreshTask = nil
            guard !self.isPlaying, let item = self.cameraPlayer.currentItem else { return }
            if self.style.camera.beauty.isActive {
                item.videoComposition = self.cameraBeautyPreview.makeVideoComposition(for: item.asset)
            }
            self.movePlayers(to: self.displayTime)
        }
    }


    var mediaDirectoryURL: URL? {
        session?.directoryURL.appendingPathComponent("media", isDirectory: true)
    }

    var canImportMedia: Bool { mediaDirectoryURL != nil && isLoaded }

    func importMedia(_ urls: [URL], atEditorTime time: TimeInterval) {
        guard let directory = mediaDirectoryURL else { return }
        mediaImportError = nil
        Task { [weak self] in
            var imageTime = time
            var audioTime = time
            var rejected: [String] = []
            for url in urls {
                guard let self, !self.isTornDown else { return }
                if RecordingOverlayImage.canImport(url) {
                    if let placed = await self.importImage(url, into: directory, atEditorTime: imageTime) {
                        imageTime = placed
                    } else {
                        rejected.append(url.lastPathComponent)
                    }
                } else if RecordingAudioClip.canImport(url) {
                    if let placed = await self.importAudio(url, into: directory, atEditorTime: audioTime) {
                        audioTime = placed
                    } else {
                        rejected.append(url.lastPathComponent)
                    }
                } else {
                    rejected.append(url.lastPathComponent)
                }
            }
            if !rejected.isEmpty {
                self?.mediaImportError = "Couldn't add \(rejected.joined(separator: ", ")). Images, GIFs and audio files can be added."
            }
        }
    }

    func importMediaFile(_ url: URL, atEditorTime time: TimeInterval) async -> Bool {
        guard let directory = mediaDirectoryURL, !isTornDown else { return false }
        if RecordingOverlayImage.canImport(url) {
            return await importImage(url, into: directory, atEditorTime: time) != nil
        }
        if RecordingAudioClip.canImport(url) {
            return await importAudio(url, into: directory, atEditorTime: time) != nil
        }
        return false
    }

    private func copyIntoProject(_ url: URL, directory: URL) -> String? {
        let fileName = UUID().uuidString + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension.lowercased())")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(fileName))
            return fileName
        } catch {
            return nil
        }
    }

    private func importImage(_ url: URL, into directory: URL, atEditorTime time: TimeInterval) async -> TimeInterval? {
        guard let fileName = copyIntoProject(url, directory: directory) else { return nil }
        let storedURL = directory.appendingPathComponent(fileName)
        let store = overlayImages
        let decoded = await Task.detached(priority: .userInitiated) { store.image(at: storedURL) }.value
        guard let decoded, !isTornDown,
              let range = sourceRange(startingAt: time, length: RecordingImageOverlay.defaultDuration,
                                      minimum: RecordingImageOverlay.minimumDuration) else {
            try? FileManager.default.removeItem(at: storedURL)
            return nil
        }
        var overlay = RecordingImageOverlay(
            fileName: fileName,
            displayName: url.deletingPathExtension().lastPathComponent,
            start: range.lowerBound,
            end: range.upperBound
        )
        overlay.aspect = decoded.aspect
        overlay.isAnimated = decoded.isAnimated
        let canvas = basePreviewCanvasSize
        let heightLimitedWidth = canvas.width > 0 ? 0.5 * canvas.height * decoded.aspect / canvas.width : 0.4
        overlay.width = min(0.4, heightLimitedWidth)
        overlayImageRevision &+= 1
        applyImages(imageOverlays + [overlay], actionName: "Add Image")
        selectImage(id: overlay.id)
        return clipTimeline.editorTime(forSourceTime: range.upperBound) ?? time + RecordingImageOverlay.defaultDuration
    }

    private func importAudio(_ url: URL, into directory: URL, atEditorTime time: TimeInterval) async -> TimeInterval? {
        guard let fileName = copyIntoProject(url, directory: directory) else { return nil }
        let storedURL = directory.appendingPathComponent(fileName)
        guard let file = await RecordingAudioFileTrack.load(url: storedURL),
              let fileDuration = try? await file.asset.load(.duration).seconds,
              fileDuration.isFinite, fileDuration >= RecordingAudioClip.minimumDuration, !isTornDown else {
            try? FileManager.default.removeItem(at: storedURL)
            return nil
        }
        audioTracksByFile[fileName] = file
        loadPeaks(for: fileName, url: storedURL)
        let start = time > duration - 0.5 ? 0 : max(0, time)
        var clip = RecordingAudioClip(
            fileName: fileName,
            displayName: url.deletingPathExtension().lastPathComponent,
            start: start,
            fileDuration: fileDuration
        )
        clip.trimEnd = min(fileDuration, max(RecordingAudioClip.minimumDuration, duration - start))
        applyAudioClips(audioClips + [clip], actionName: "Add Audio")
        selectAudioClip(id: clip.id)
        return clip.end
    }

    private func loadPeaks(for fileName: String, url: URL) {
        guard audioPeaks[fileName] == nil else { return }
        Task { [weak self] in
            let peaks = await Task.detached(priority: .utility) { await RecordingAudioPeaks.load(url: url) }.value
            self?.audioPeaks[fileName] = peaks
        }
    }

    private func loadOverlayMedia() {
        mediaLoadTask?.cancel()
        guard let directory = mediaDirectoryURL, !imageOverlays.isEmpty || !audioClips.isEmpty else { return }
        let imageFiles = Set(imageOverlays.map(\.fileName))
        let audioFiles = Set(audioClips.map(\.fileName)).subtracting(audioTracksByFile.keys)
        let store = overlayImages
        mediaLoadTask = Task { [weak self] in
            await Task.detached(priority: .userInitiated) {
                for name in imageFiles {
                    _ = store.image(at: directory.appendingPathComponent(name))
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.overlayImageRevision &+= 1
            var resolvedAny = false
            for name in audioFiles {
                let url = directory.appendingPathComponent(name)
                if let file = await RecordingAudioFileTrack.load(url: url) {
                    guard !Task.isCancelled else { return }
                    self.audioTracksByFile[name] = file
                    resolvedAny = true
                }
                self.loadPeaks(for: name, url: url)
            }
            if resolvedAny, self.isLoaded {
                try? self.rebuildScreenPlayerItem(preserving: self.currentTime)
            }
        }
    }

    private func addingAudioClips(to asset: AVAsset) throws -> AVAsset {
        playbackClipTrackIDs = [:]
        let sources = audioClips.compactMap { clip in
            audioTracksByFile[clip.fileName].map { RecordingAudioClipSource(clip: clip, file: $0) }
        }
        guard !sources.isEmpty else { return asset }
        let composition: AVMutableComposition
        if let existing = asset as? AVMutableComposition {
            composition = existing
        } else {
            composition = AVMutableComposition()
            try composition.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: sourceDuration, preferredTimescale: 600)),
                of: asset,
                at: .zero
            )
        }
        playbackClipTrackIDs = RecordingAudioClipMixer.insert(sources, into: composition, videoDuration: duration)
        return composition
    }


    var selectedImage: RecordingImageOverlay? {
        imageOverlays.first { $0.id == selectedImageID }
    }

    var imageTimelineBlocks: [RecordingOverlayTimelineBlock<RecordingImageOverlay>] {
        RecordingOverlayTimelineBlock.blocks(for: imageOverlays, clipTimeline: clipTimeline) {
            ($0.start, $0.end)
        }
    }

    func images(atEditorTime time: TimeInterval) -> [RecordingImageOverlay] {
        guard !imageOverlays.isEmpty, clipTimeline.location(at: time) != nil else { return [] }
        let sourceTime = clipTimeline.sourceTime(at: time)
        return imageOverlays.filter { $0.isActive(atSourceTime: sourceTime) }
    }

    func overlayImageURL(for overlay: RecordingImageOverlay) -> URL? {
        mediaDirectoryURL?.appendingPathComponent(overlay.fileName)
    }

    func selectImage(id: UUID) {
        guard imageOverlays.contains(where: { $0.id == id }) else { return }
        clearTimelineSelection()
        selectedImageID = id
    }

    func removeImage(id: UUID) {
        applyImages(imageOverlays.filter { $0.id != id }, actionName: "Remove Image")
        if selectedImageID == id { selectedImageID = nil }
    }

    func beginImageEdit() {
        if imageEditSnapshot == nil { imageEditSnapshot = imageOverlays }
    }

    func endImageEdit(actionName: String = "Edit Image") {
        guard let previous = imageEditSnapshot else { return }
        imageEditSnapshot = nil
        guard previous != imageOverlays else { return }
        registerUndo(actionName) { target in
            target.applyImages(previous, actionName: actionName)
        }
    }

    func setImage(_ overlay: RecordingImageOverlay) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        var updated = overlay
        let range = clampedSourceRange(start: overlay.start, end: overlay.end, minimum: RecordingImageOverlay.minimumDuration)
        updated.start = range.lowerBound
        updated.end = range.upperBound
        updated.width = min(max(updated.width, RecordingImageOverlay.widthRange.lowerBound),
                            RecordingImageOverlay.widthRange.upperBound)
        updated.center = CGPoint(x: min(max(updated.center.x, 0), 1), y: min(max(updated.center.y, 0), 1))
        updated.opacity = min(max(updated.opacity, 0), 1)
        var all = imageOverlays
        all[index] = updated
        imageOverlays = all
        scheduleProjectSave()
    }

    func editImage(_ overlay: RecordingImageOverlay, actionName: String) {
        beginImageEdit()
        setImage(overlay)
        imageCoalesceTask?.cancel()
        imageCoalesceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.endImageEdit(actionName: actionName)
        }
    }

    private func applyImages(_ all: [RecordingImageOverlay], actionName: String) {
        guard all != imageOverlays else { return }
        let previous = imageOverlays
        registerUndo(actionName) { target in
            target.applyImages(previous, actionName: actionName)
        }
        imageOverlays = all
        scheduleProjectSave()
        if let selectedImageID, !all.contains(where: { $0.id == selectedImageID }) {
            self.selectedImageID = nil
        }
    }


    var selectedAudioClip: RecordingAudioClip? {
        audioClips.first { $0.id == selectedAudioClipID }
    }

    func selectAudioClip(id: UUID) {
        guard audioClips.contains(where: { $0.id == id }) else { return }
        clearTimelineSelection()
        selectedAudioClipID = id
    }

    func removeAudioClip(id: UUID) {
        applyAudioClips(audioClips.filter { $0.id != id }, actionName: "Remove Audio")
        if selectedAudioClipID == id { selectedAudioClipID = nil }
    }

    func beginAudioClipEdit() {
        if audioEditSnapshot == nil { audioEditSnapshot = audioClips }
    }

    func endAudioClipEdit(actionName: String = "Edit Audio") {
        guard let previous = audioEditSnapshot else { return }
        audioEditSnapshot = nil
        guard previous != audioClips else { return }
        registerUndo(actionName) { target in
            target.applyAudioClips(previous, actionName: actionName)
        }
    }

    func setAudioClip(_ clip: RecordingAudioClip) {
        guard let index = audioClips.firstIndex(where: { $0.id == clip.id }) else { return }
        var updated = clip
        let minimum = RecordingAudioClip.minimumDuration
        updated.trimStart = min(max(0, updated.trimStart), max(0, updated.fileDuration - minimum))
        updated.trimEnd = min(max(updated.trimEnd, updated.trimStart + minimum), updated.fileDuration)
        updated.start = max(0, updated.start)
        updated.volume = min(max(updated.volume, 0), 1)
        var all = audioClips
        all[index] = updated
        replaceAudioClips(all)
    }

    func editAudioClip(_ clip: RecordingAudioClip, actionName: String) {
        beginAudioClipEdit()
        setAudioClip(clip)
        audioCoalesceTask?.cancel()
        audioCoalesceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.endAudioClipEdit(actionName: actionName)
        }
    }

    private func replaceAudioClips(_ all: [RecordingAudioClip]) {
        let previous = audioClips
        audioClips = all
        scheduleProjectSave()
        let placement: (RecordingAudioClip) -> [Double] = { [$0.start, $0.trimStart, $0.trimEnd] }
        let movedAudio = previous.map(\.id) != all.map(\.id)
            || zip(previous, all).contains { placement($0) != placement($1) || $0.fileName != $1.fileName }
        if movedAudio {
            scheduleAudioPlaybackRebuild()
        } else {
            updatePlaybackVolume()
        }
    }

    private func scheduleAudioPlaybackRebuild() {
        audioPlaybackRebuildTask?.cancel()
        audioPlaybackRebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled, self.isLoaded else { return }
            let wasPlaying = self.isPlaying
            self.pause()
            try? self.rebuildScreenPlayerItem(preserving: self.currentTime)
            if wasPlaying { self.play() }
        }
    }

    private func applyAudioClips(_ all: [RecordingAudioClip], actionName: String) {
        guard all != audioClips else { return }
        let previous = audioClips
        registerUndo(actionName) { target in
            target.applyAudioClips(previous, actionName: actionName)
        }
        replaceAudioClips(all)
        if let selectedAudioClipID, !all.contains(where: { $0.id == selectedAudioClipID }) {
            self.selectedAudioClipID = nil
        }
    }


    private func sourceRange(
        startingAt editorTime: TimeInterval,
        length: TimeInterval,
        minimum: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard sourceDuration >= minimum else { return nil }
        let source = clipTimeline.sourceTime(at: min(max(editorTime, 0), duration))
        let start = min(max(0, source), sourceDuration - minimum)
        return start...min(sourceDuration, start + length)
    }

    private func sourceRange(
        fromEditorTime editorStart: TimeInterval,
        toEditorTime editorEnd: TimeInterval,
        minimum: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        guard sourceDuration >= minimum else { return nil }
        let low = clipTimeline.sourceTime(at: min(editorStart, editorEnd))
        let high = clipTimeline.sourceTime(at: max(editorStart, editorEnd))
        return clampedSourceRange(start: low, end: high, minimum: minimum)
    }

    private func clampedSourceRange(start: TimeInterval, end: TimeInterval, minimum: TimeInterval) -> ClosedRange<TimeInterval> {
        let lower = min(max(0, start), max(0, sourceDuration - minimum))
        let upper = min(max(end, lower + minimum), sourceDuration)
        return lower...max(lower, upper)
    }

    private func drawnSourceSpan(
        for range: ClosedRange<TimeInterval>,
        among occupied: [ClosedRange<TimeInterval>],
        minimum: TimeInterval
    ) -> ClosedRange<TimeInterval>? {
        var lower = min(max(0, clipTimeline.sourceTime(at: range.lowerBound)), sourceDuration)
        let end = min(max(lower, clipTimeline.sourceTime(at: range.upperBound)), sourceDuration)
        while let covering = occupied.first(where: { $0.lowerBound <= lower && lower < $0.upperBound }) {
            lower = covering.upperBound
        }
        let ceiling = occupied.map(\.lowerBound).filter { $0 >= lower }.min() ?? sourceDuration
        let upper = min(end, ceiling)
        guard upper - lower >= minimum - 0.001 else { return nil }
        return lower...upper
    }

    var visibleRecordedPressTimes: [TimeInterval] {
        recordedPressTimes.compactMap { clipTimeline.editorTime(forSourceTime: $0) }
    }

    var zoomTimelineBlocks: [RecordingZoomTimelineBlock] {
        zoomCues
            .filter { !$0.isImplicit }
            .compactMap { cue in
                let slices = clipTimeline.slices(overlapping: cue.start, sourceEnd: cue.end)
                guard let first = slices.first, let last = slices.last else { return nil }
                return RecordingZoomTimelineBlock(
                    cue: cue,
                    editorStart: first.editorStart,
                    editorEnd: last.editorEnd
                )
            }
    }

    func sourceTime(atEditorTime time: TimeInterval) -> TimeInterval {
        clipTimeline.sourceTime(at: time)
    }

    func editorTime(forSourceTime time: TimeInterval) -> TimeInterval? {
        clipTimeline.editorTime(forSourceTime: time)
    }

    private func rebuildPointerTimeline() {
        reframeFocusTimeline = nil
        reframeFocusResolved = false
        guard pointerIsSynthesized, sourceDuration > 0 else {
            pointerTimeline = .empty
            return
        }
        pointerTimeline = PointerTimeline.build(
            capture: pointerCapture,
            duration: sourceDuration,
            recordingSizeInPoints: recordingPointSize,
            fallbackArtwork: PointerArtworkCapture.defaultArtwork(),
            clipTimeline: clipTimeline
        )
    }

    private func scheduleViewportRebuild() {
        viewportRebuildTask?.cancel()
        viewportRebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            self.viewportRebuildTask = nil
            self.rebuildViewportTimeline()
        }
    }

    private func rebuildViewportTimeline() {
        rebuildCameraLayoutTimeline(rebuildsZoom: false)
        guard sourceDuration > 0 else {
            viewportTimeline = .identity
            return
        }
        viewportTimeline = ViewportTimeline.build(
            cues: zoomCues,
            capture: pointerCapture,
            clipTimeline: clipTimeline
        )
        rebuildPreviewReframe()
    }

    private func scheduleProjectSave() {
        guard isLoaded, !isApplyingDocument, session != nil else { return }
        hasUnsavedChanges = true
        projectSaveTask?.cancel()
        projectSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.writeDraftNow()
        }
    }

    private func currentDocument() -> RecordingEditDocument {
        RecordingEditDocument(
            style: style,
            zoomEnabled: zoomEnabled,
            zoomCues: zoomCues.filter { !$0.isImplicit },
            cameraLayoutCues: cameraLayoutCues.isEmpty ? nil : cameraLayoutCues,
            textOverlays: textOverlays.isEmpty ? nil : textOverlays,
            redactions: redactions.isEmpty ? nil : redactions,
            imageOverlays: imageOverlays.isEmpty ? nil : imageOverlays,
            audioClips: audioClips.isEmpty ? nil : audioClips,
            clipTimeline: clipTimeline,
            exportSettings: exportSettings,
            showsClickEffects: showsClickEffects,
            showsKeystrokes: showsKeystrokes,
            keystrokePlacement: keystrokePlacement,
            showsSpeedBadge: showsSpeedBadge ? true : nil,
            speedBadgePlacement: speedBadgePlacement == .topRight ? nil : speedBadgePlacement,
            showsSubtitles: showsSubtitles,
            subtitleCues: subtitleCues.isEmpty ? nil : subtitleCues,
            subtitleWords: transcriptWords.isEmpty ? nil : transcriptWords,
            subtitleStyle: subtitleStyle,
            exportAspect: exportAspect,
            exportAspectMode: exportAspectMode,
            videoCropRect: isVideoCropped ? videoCropRect : nil,
            replacementAudioFileName: replacementAudio?.url.lastPathComponent,
            replacementAudioDisplayName: replacementAudio?.displayName,
            audioExportFormat: audioExportFormat,
            audioVolume: Double(audioVolume)
        )
    }

    var hasNeverBeenSaved: Bool {
        guard let session else { return false }
        return !session.hasSavedProject
    }

    private func writeDraftNow() {
        guard isLoaded, let session else { return }
        let document = currentDocument()
        if document == lastSavedDocument {
            session.removeDraftDocument()
            hasUnsavedChanges = false
        } else {
            try? session.writeDraftDocument(document)
            hasUnsavedChanges = true
        }
        dropStaleRender(for: document, in: session)
    }

    private func dropStaleRender(for document: RecordingEditDocument, in session: RecordingSession) {
        guard session.existingFinalURL != nil else { return }
        guard session.freshFinalURL(matching: document) == nil else { return }
        session.removeFinalVideos()
    }

    func flushDraft() {
        projectSaveTask?.cancel()
        writeDraftNow()
    }


    var editDocument: RecordingEditDocument {
        currentDocument()
    }

    func performAgentEdit(_ edit: () throws -> Void) rethrows {
        let manager = editUndoManager
        closeOpenUndoGroups()
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        defer {
            manager.endUndoGrouping()
            manager.groupsByEvent = true
        }
        try edit()
    }

    func closeOpenUndoGroups() {
        while editUndoManager.groupingLevel > 0 {
            editUndoManager.endUndoGrouping()
        }
    }

    func applyAgentDocument(_ requested: RecordingEditDocument, actionName: String) {
        guard isLoaded else { return }
        var document = requested
        let previous = currentDocument()
        document.replacementAudioFileName = previous.replacementAudioFileName
        document.replacementAudioDisplayName = previous.replacementAudioDisplayName
        guard document != previous else { return }

        registerUndo(actionName) { target in
            target.applyAgentDocument(previous, actionName: actionName)
        }
        pause()
        clearTimelineSelection()
        hoverPreviewTime = nil
        timelineHoverTime = nil

        let implicitZoomCues = zoomCues.filter(\.isImplicit)
        applyDocumentSettings(document)
        isApplyingDocument = true
        zoomCues = document.zoomCues + implicitZoomCues
        if let clips = document.clips, !clips.isEmpty {
            clipTimeline = RecordingClipTimeline(segments: clips).normalized(to: sourceDuration)
        }
        duration = clipTimeline.duration
        isApplyingDocument = false

        try? rebuildScreenPlayerItem(preserving: min(currentTime, duration))
        rebuildCameraLayoutTimeline()
        rebuildPointerTimeline()
        rebuildViewportTimeline()
        rebuildPreviewReframe()
        updateActiveTranscriptWord()
        scheduleProjectSave()
    }

    @discardableResult
    func saveProject() -> Bool {
        guard isLoaded, let session else { return false }
        projectSaveTask?.cancel()
        let document = currentDocument()
        do {
            try session.writeEditDocument(document)
            session.removeDraftDocument()
            lastSavedDocument = document
            hasUnsavedChanges = false
            session.updateProjectMetadata { $0.savedAt = Date() }
            dropStaleRender(for: document, in: session)
            RecordingProjectStore.shared.reload()
            flashSaveConfirmation()
            return true
        } catch {
            FailureAlert.present(message: "The recording project could not be saved", error: error,
                                 detail: "Your editor will stay open. Try saving again after resolving the problem.")
            return false
        }
    }

    func discardChanges() async {
        guard isLoaded, let session else { return }
        projectSaveTask?.cancel()
        session.removeDraftDocument()
        guard let document = lastSavedDocument else { return }
        applyDocumentSettings(document)
        await applyDocumentTimeline(document)
        flushDraft()
    }

    func deleteProject() {
        guard let session else { return }
        teardown()
        RecordingProjectStore.shared.delete(session)
    }

    private func flashSaveConfirmation() {
        saveFlash = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            self?.saveFlash = false
        }
    }

    private func applyDocumentTimeline(_ document: RecordingEditDocument) async {
        guard !isTornDown, !Task.isCancelled, let session else { return }
        isApplyingDocument = true
        defer { isApplyingDocument = false }

        if let storedClips = document.clips, !storedClips.isEmpty {
            clipTimeline = RecordingClipTimeline(segments: storedClips)
                .normalized(to: sourceDuration)
        } else {
            clipTimeline = .legacyTrim(
                start: document.trimStart,
                end: document.trimEnd,
                sourceDuration: sourceDuration
            )
        }
        duration = clipTimeline.duration
        selectedClipID = nil

        if let fileName = document.replacementAudioFileName {
            let url = session.directoryURL.appendingPathComponent(fileName)
            if url != replacementAudio?.url, FileManager.default.fileExists(atPath: url.path) {
                let loadedAudio = await RecordingReplacementAudio.load(
                    url: url,
                    displayName: document.replacementAudioDisplayName ?? fileName
                )
                guard !isTornDown, !Task.isCancelled else { return }
                replacementAudio = loadedAudio
            }
        } else {
            replacementAudio = nil
        }

        isApplyingDocument = false

        try? rebuildScreenPlayerItem(preserving: currentTime)
        rebuildPointerTimeline()
        rebuildViewportTimeline()
        rebuildPreviewReframe()
        editUndoManager.removeAllActions()
        undoRevision += 1
    }

    func viewportFrame(at time: TimeInterval) -> ViewportFrame {
        guard zoomEnabled else { return .identity }
        return viewportTimeline.frame(at: time)
    }

    func zoomProgress(at time: TimeInterval) -> Double {
        guard zoomEnabled else { return 0 }
        return viewportTimeline.zoomProgress(at: time)
    }

    var pointerIsSynthesized: Bool {
        manifest?.pointerSynthesized == true
    }

    func pointerLocation(at time: TimeInterval) -> CGPoint? {
        guard pointerIsSynthesized else { return nil }
        return pointerTimeline.location(at: time)
    }

    func pointerFrame(at time: TimeInterval) -> PointerFrame? {
        guard !style.hidesCursor, pointerIsSynthesized else { return nil }
        return pointerTimeline.frame(at: time)
    }

    func artwork(id: String?) -> PointerArtwork? {
        pointerTimeline.artwork(id: id)?.styled(style.cursorStyle, inverted: style.invertsCursor)
    }

    var canShowPressEffects: Bool {
        pointerIsSynthesized && manifest?.pressEffectsBaked == false
    }

    var showsPressEffects: Bool {
        canShowPressEffects && showsClickEffects
    }

    var hasKeystrokes: Bool {
        !pointerCapture.keystrokes.isEmpty
    }


    var canTranscribe: Bool {
        manifest?.includesMicrophone == true
    }

    var hasSubtitles: Bool {
        !subtitleTimeline.isEmpty
    }

    func subtitleText(at time: TimeInterval) -> String? {
        guard showsSubtitles, hasSubtitles else { return nil }
        return subtitleTimeline.text(at: clipTimeline.sourceTime(at: time))
    }

    func subtitleKaraokeLine(at time: TimeInterval) -> KaraokeTimeline.Line? {
        guard showsSubtitles, subtitleStyle.highlightsSpokenWord,
              !karaokeTimeline.isEmpty else {
            return nil
        }
        return karaokeTimeline.line(at: clipTimeline.sourceTime(at: time))
    }

    func transcribe() {
        guard !transcriptionState.isTranscribing, isLoaded else { return }
        transcriptionState = .transcribing
        let movieURL = screenURL
        transcriptionTask = Task { [weak self] in
            do {
                let transcript = try await RecordingTranscriptionService.transcribe(screenMovieURL: movieURL)
                guard !Task.isCancelled else { return }
                self?.applyTranscription(transcript)
            } catch {
                guard !Task.isCancelled else { return }
                self?.transcriptionState = .failed(error.localizedDescription)
            }
        }
    }

    private func applyTranscription(_ transcript: RecordingTranscript) {
        subtitleCues = transcript.cues
        subtitleTimeline = SubtitleTimeline(cues: transcript.cues)
        transcriptWords = transcript.words
        karaokeTimeline = KaraokeTimeline(cues: transcript.cues, words: transcript.words)
        showsSubtitles = true
        transcriptionState = .idle
        updateActiveTranscriptWord()
        scheduleProjectSave()
    }

    func removeTranscription() {
        subtitleCues = []
        subtitleTimeline = .empty
        transcriptWords = []
        karaokeTimeline = .empty
        activeTranscriptWordIndex = nil
        transcriptionState = .idle
        scheduleProjectSave()
    }

    func updateSubtitleText(id: UUID, text: String) {
        guard let index = subtitleCues.firstIndex(where: { $0.id == id }),
              subtitleCues[index].text != text else {
            return
        }
        subtitleCues[index].text = text
        subtitleTimeline = SubtitleTimeline(cues: subtitleCues)
        karaokeTimeline = KaraokeTimeline(cues: subtitleCues, words: transcriptWords)
        scheduleProjectSave()
    }

    func seekToSubtitle(_ cue: RecordingSubtitleCue) {
        let target = clipTimeline.editorTime(forSourceTime: cue.start)
            ?? clipTimeline.editorTime(forSourceTime: (cue.start + cue.end) / 2)
        guard let target else { return }
        pause()
        seek(to: target)
    }

    var activeSubtitleCue: RecordingSubtitleCue? {
        guard hasSubtitles else { return nil }
        return subtitleTimeline.cue(at: clipTimeline.sourceTime(at: currentTime))
    }


    var hasTranscriptWords: Bool {
        !transcriptWords.isEmpty
    }

    func transcriptWordSurvives(_ index: Int) -> Bool {
        guard transcriptWords.indices.contains(index) else { return false }
        return clipTimeline.editorTime(forSourceTime: transcriptWords[index].midpoint) != nil
    }

    func isFillerWord(_ index: Int) -> Bool {
        guard transcriptWords.indices.contains(index) else { return false }
        return TranscriptEditPlanner.isFiller(transcriptWords[index])
    }

    var removableFillerWordCount: Int {
        TranscriptEditPlanner.fillerIndices(in: transcriptWords)
            .count { transcriptWordSurvives($0) }
    }

    var trimmableSilenceCount: Int {
        TranscriptEditPlanner.silenceCutRanges(in: transcriptWords, sourceDuration: sourceDuration)
            .count { !clipTimeline.slices(overlapping: $0.lowerBound, sourceEnd: $0.upperBound).isEmpty }
    }

    func seekToTranscriptWord(at index: Int) {
        guard transcriptWords.indices.contains(index) else { return }
        let word = transcriptWords[index]
        let target = clipTimeline.editorTime(forSourceTime: word.start)
            ?? clipTimeline.editorTime(forSourceTime: word.midpoint)
        guard let target else { return }
        pause()
        seek(to: target)
    }

    func cutTranscriptWords(in range: ClosedRange<Int>) {
        guard let cut = TranscriptEditPlanner.cutRange(
            forWordsAt: range,
            in: transcriptWords,
            sourceDuration: sourceDuration
        ) else { return }
        cutSourceRanges([cut], actionName: range.count == 1 ? "Cut Word" : "Cut Words")
    }

    func removeFillerWords() {
        cutSourceRanges(
            TranscriptEditPlanner.fillerCutRanges(in: transcriptWords, sourceDuration: sourceDuration),
            actionName: "Remove Filler Words"
        )
    }

    func trimNarrationSilences() {
        cutSourceRanges(
            TranscriptEditPlanner.silenceCutRanges(in: transcriptWords, sourceDuration: sourceDuration),
            actionName: "Trim Silences"
        )
    }

    func cutSourceRanges(_ ranges: [ClosedRange<TimeInterval>], actionName: String) {
        let merged = RecordingClipTimeline.mergedRanges(ranges)
        guard !merged.isEmpty,
              let next = clipTimeline.removingSourceRanges(merged)?.normalized(to: sourceDuration),
              next != clipTimeline else {
            return
        }

        let updatedCues = Self.rebuildingCueTexts(
            subtitleCues,
            words: transcriptWords,
            cutRanges: merged,
            surviving: next
        )
        if updatedCues != subtitleCues {
            applySubtitleCues(updatedCues, actionName: actionName)
        }

        let playhead = next.editorTime(forSourceTime: merged[0].upperBound)
            ?? min(currentTime, next.duration)
        applyClipTimeline(
            next,
            selectedID: selectedClipID,
            playheadTime: playhead,
            actionName: actionName
        )
    }

    private func applySubtitleCues(_ cues: [RecordingSubtitleCue], actionName: String) {
        guard cues != subtitleCues else { return }
        let previous = subtitleCues
        registerUndo(actionName) { target in
            target.applySubtitleCues(previous, actionName: actionName)
        }
        subtitleCues = cues
        subtitleTimeline = SubtitleTimeline(cues: cues)
        karaokeTimeline = KaraokeTimeline(cues: cues, words: transcriptWords)
        scheduleProjectSave()
    }

    private static func rebuildingCueTexts(
        _ cues: [RecordingSubtitleCue],
        words: [RecordingTranscriptWord],
        cutRanges: [ClosedRange<TimeInterval>],
        surviving timeline: RecordingClipTimeline
    ) -> [RecordingSubtitleCue] {
        guard !words.isEmpty, !cues.isEmpty else { return cues }
        var result = cues
        let byStart = result.indices.sorted { result[$0].start < result[$1].start }

        for (position, index) in byStart.enumerated() {
            let cue = result[index]
            let overlapsCut = cutRanges.contains {
                $0.lowerBound < cue.end && $0.upperBound > cue.start
            }
            guard overlapsCut else { continue }

            let nextCueStart = position < byStart.count - 1
                ? result[byStart[position + 1]].start
                : .infinity
            result[index].text = words
                .filter { word in
                    word.start >= cue.start - 0.001
                        && word.start < nextCueStart - 0.001
                        && timeline.editorTime(forSourceTime: word.midpoint) != nil
                }
                .map(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private func updateActiveTranscriptWord() {
        guard !transcriptWords.isEmpty else {
            if activeTranscriptWordIndex != nil {
                activeTranscriptWordIndex = nil
            }
            return
        }
        let index = Self.transcriptWordIndex(
            at: clipTimeline.sourceTime(at: currentTime),
            in: transcriptWords
        )
        if activeTranscriptWordIndex != index {
            activeTranscriptWordIndex = index
        }
    }

    private static func transcriptWordIndex(
        at sourceTime: TimeInterval,
        in words: [RecordingTranscriptWord]
    ) -> Int? {
        guard sourceTime.isFinite, !words.isEmpty else { return nil }
        var low = 0
        var high = words.count
        while low < high {
            let middle = (low + high) / 2
            if words[middle].start <= sourceTime {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        guard index >= 0 else { return nil }
        return sourceTime <= words[index].end + 0.25 ? index : nil
    }

    var hasSpedUpClips: Bool {
        !speedBadgeTimeline.isEmpty
    }

    func speedBadge(at time: TimeInterval) -> SpeedBadgeFrame? {
        guard showsSpeedBadge else { return nil }
        return speedBadgeTimeline.frame(at: time)
    }

    func keystrokeCaption(at time: TimeInterval) -> KeystrokeCaptionFrame? {
        guard showsKeystrokes, hasKeystrokes else { return nil }
        return keystrokeTimeline.frame(at: clipTimeline.sourceTime(at: time))
    }

    private var recordingPointSize: CGSize {
        let scale = max(CGFloat(manifest?.pixelScale ?? 1), 1)
        return CGSize(width: videoSize.width / scale, height: videoSize.height / scale)
    }


    var isVideoCropped: Bool {
        RecordingVideoCropGeometry.isCropped(videoCropRect)
    }

    var videoCropPixelSize: CGSize {
        let crop = isCroppingVideo ? workingVideoCropRect : videoCropRect
        return CGSize(
            width: (videoSize.width * crop.width).rounded(),
            height: (videoSize.height * crop.height).rounded()
        )
    }

    func beginVideoCrop() {
        guard !isCroppingVideo, videoSize.width > 0, videoSize.height > 0 else {
            return
        }
        pause()
        workingVideoCropRect = videoCropRect
        videoCropAspect = .freeform
        videoCropDrag = nil
        isCroppingVideo = true
    }

    func cancelVideoCrop() {
        guard isCroppingVideo else { return }
        workingVideoCropRect = videoCropRect
        videoCropAspect = .freeform
        videoCropDrag = nil
        isCroppingVideo = false
    }

    func resetVideoCrop() {
        guard isCroppingVideo else { return }
        if let ratio = videoCropAspect.pixelRatio(imageSize: videoSize) {
            workingVideoCropRect = normalizedVideoCrop(
                CropGeometry.snapped(CropGeometry.largest(aspect: ratio, in: videoCropBounds), in: videoCropBounds)
            )
        } else {
            workingVideoCropRect = CropGeometry.unit
        }
    }

    func setVideoCropAspect(_ aspect: CropAspectRatio) {
        videoCropAspect = aspect
        guard isCroppingVideo,
              let ratio = aspect.pixelRatio(imageSize: videoSize) else {
            return
        }
        workingVideoCropRect = normalizedVideoCrop(CropGeometry.snapped(
            CropGeometry.reshaped(pixelVideoCrop(workingVideoCropRect), aspect: ratio, in: videoCropBounds),
            in: videoCropBounds
        ))
    }

    func nudgeVideoCrop(by delta: CGSize) {
        guard isCroppingVideo, videoCropDrag == nil else { return }
        workingVideoCropRect = normalizedVideoCrop(CropGeometry.snapped(
            CropGeometry.move(pixelVideoCrop(workingVideoCropRect), by: delta, in: videoCropBounds),
            in: videoCropBounds
        ))
    }


    var isVideoCropDragging: Bool { videoCropDrag != nil }

    func videoCropViewRect(in videoFrame: CGRect) -> CGRect {
        let crop = workingVideoCropRect.standardized
        return CGRect(
            x: videoFrame.minX + crop.minX * videoFrame.width,
            y: videoFrame.minY + crop.minY * videoFrame.height,
            width: crop.width * videoFrame.width,
            height: crop.height * videoFrame.height
        )
    }

    func videoCropTarget(at pointer: CGPoint, in videoFrame: CGRect) -> CropDragTarget {
        CropHitTest.target(at: pointer, box: videoCropViewRect(in: videoFrame))
    }

    func beginVideoCropDrag(at pointer: CGPoint, in videoFrame: CGRect) {
        guard isCroppingVideo, let point = videoCropPixelPoint(at: pointer, in: videoFrame) else { return }
        let target = videoCropTarget(at: pointer, in: videoFrame)
        videoCropDrag = CropDrag(
            target: target,
            startRect: pixelVideoCrop(workingVideoCropRect),
            startPoint: point,
            startPointer: pointer,
            pointer: pointer,
            hasTravelled: target != .newSelection
        )
    }

    func updateVideoCropDrag(to pointer: CGPoint, in videoFrame: CGRect) {
        guard var drag = videoCropDrag else { return }
        drag.pointer = pointer
        if !drag.hasTravelled {
            drag.hasTravelled = hypot(pointer.x - drag.startPointer.x, pointer.y - drag.startPointer.y) >= 3
        }
        videoCropDrag = drag
        guard drag.hasTravelled, let point = videoCropPixelPoint(at: pointer, in: videoFrame) else { return }

        let flags = NSEvent.modifierFlags
        workingVideoCropRect = normalizedVideoCrop(drag.rect(
            at: point,
            in: videoCropBounds,
            lockedAspect: videoCropAspect.pixelRatio(imageSize: videoSize),
            minimumSize: CGSize(width: min(24, videoSize.width), height: min(24, videoSize.height)),
            holdsAspect: flags.contains(.shift),
            fromCenter: flags.contains(.option)
        ))
    }

    func endVideoCropDrag() {
        videoCropDrag = nil
    }

    private func videoCropPixelPoint(at pointer: CGPoint, in videoFrame: CGRect) -> CGPoint? {
        guard videoFrame.width > 0, videoFrame.height > 0 else { return nil }
        return CGPoint(
            x: (pointer.x - videoFrame.minX) * videoSize.width / videoFrame.width,
            y: (pointer.y - videoFrame.minY) * videoSize.height / videoFrame.height
        )
    }

    private var videoCropBounds: CGRect { CGRect(origin: .zero, size: videoSize) }

    private func pixelVideoCrop(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * videoSize.width,
            y: rect.minY * videoSize.height,
            width: rect.width * videoSize.width,
            height: rect.height * videoSize.height
        )
    }

    private func normalizedVideoCrop(_ rect: CGRect) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else { return CropGeometry.unit }
        return CGRect(
            x: rect.minX / videoSize.width,
            y: rect.minY / videoSize.height,
            width: rect.width / videoSize.width,
            height: rect.height / videoSize.height
        )
    }

    func applyVideoCrop() {
        guard isCroppingVideo else { return }
        let next = RecordingVideoCropGeometry.normalized(workingVideoCropRect)
        isCroppingVideo = false
        videoCropAspect = .freeform
        workingVideoCropRect = next
        applyVideoCrop(next, actionName: "Crop Video")
    }

    private func applyVideoCrop(_ requested: CGRect, actionName: String) {
        let next = RecordingVideoCropGeometry.normalized(requested)
        guard next != videoCropRect else { return }
        let previous = videoCropRect
        registerUndo(actionName) { target in
            target.applyVideoCrop(previous, actionName: actionName)
        }
        videoCropRect = next
    }

    var showsCameraLayer: Bool {
        hasCameraVideo && style.camera.isVisible
    }


    private func makeExportConfiguration(includesGIF: Bool = false) -> RecordingStudioExporter.Configuration {
        let reframe = makeReframeTrack()
        let fitContentAspect: CGFloat? =
            (exportAspect == .original || exportAspectMode == .fit) && videoSize.height > 0
                ? videoSize.width / videoSize.height
                : nil
        var configuration = RecordingStudioExporter.Configuration(
            screenURL: screenURL,
            cameraURL: showsCameraLayer && cameraLayoutTimeline.usesCamera ? session?.cameraURL : nil,
            cameraOffset: cameraOffset,
            cameraAspect: cameraVideoAspect,
            style: style,
            cameraLayoutTimeline: cameraLayoutTimeline,
            viewportTimeline: zoomEnabled ? viewportTimeline : .identity,
            pointerTimeline: pointerIsSynthesized
                ? pointerTimeline.mappingArtwork {
                    $0.styled(style.cursorStyle, inverted: style.invertsCursor)
                }
                : nil,
            showsPressEffects: showsPressEffects,
            keystrokeTimeline: showsKeystrokes && hasKeystrokes ? keystrokeTimeline : nil,
            keystrokePlacement: keystrokePlacement,
            speedBadgeTimeline: showsSpeedBadge && !speedBadgeTimeline.isEmpty ? speedBadgeTimeline : nil,
            speedBadgePlacement: speedBadgePlacement,
            subtitleTimeline: showsSubtitles && hasSubtitles ? subtitleTimeline : nil,
            subtitleStyle: subtitleStyle,
            karaokeTimeline: showsSubtitles && hasSubtitles && !karaokeTimeline.isEmpty
                ? karaokeTimeline
                : nil,
            canvasSize: basePreviewCanvasSize,
            videoCropRect: videoCropRect,
            clipTimeline: clipTimeline,
            exportSettings: exportSettings,
            audioReplacementURL: replacementAudio?.url,
            audioVolume: Double(audioVolume),
            reframe: reframe,
            fitContentAspect: fitContentAspect,
            usesUniformPadding: exportAspect == .original,
            motionTimeline: makeMotionTimeline(reframe: reframe),
            textOverlays: textOverlays,
            redactions: redactions,
            imageOverlays: imageOverlays,
            audioClips: audioClips,
            mediaDirectory: mediaDirectoryURL
        )
        configuration.appearance = exportAppearance
        configuration.deliveryOptions = exportDeliveryOptions
        if !includesGIF { configuration.deliveryOptions.format = .video }
        configuration.sourcePixelScale = manifest?.pixelScale ?? 1
        configuration.recordedAudioTrackNames = [
            manifest?.includesSystemAudio == true ? "System Audio" : nil,
            manifest?.includesMicrophone == true ? "Microphone" : nil
        ].compactMap { $0 }
        return configuration
    }

    private func makeMotionTimeline(reframe: ReframeTrack?) -> RecordingStudioMotionTimeline {
        guard sourceDuration > 0 else { return .none }
        let fitContentAspect: CGFloat? =
            (exportAspect == .original || exportAspectMode == .fit) && videoSize.height > 0
                ? videoSize.width / videoSize.height
                : nil
        return RecordingStudioMotionTimeline.build(
            canvasSize: basePreviewCanvasSize,
            style: style,
            usesUniformPadding: exportAspect == .original,
            contentAspect: reframe?.sourceAspect ?? fitContentAspect,
            contentMode: fitContentAspect != nil && reframe == nil ? .fit : .fill,
            contentCropRect: videoCropRect,
            showsCamera: showsCameraLayer,
            cameraAspect: cameraVideoAspect,
            layoutTimeline: cameraLayoutTimeline,
            cues: zoomEnabled ? zoomCues : [],
            capture: pointerCapture,
            clipTimeline: clipTimeline,
            zoomAnimationStyle: exportAppearance.zoomAnimationStyle
        )
    }

    private func rebuildMotionTimeline() {
        guard isLoaded else { return }
        motionTimeline = makeMotionTimeline(reframe: previewReframe)
    }

    private func makeReframeTrack() -> ReframeTrack? {
        guard exportAspect != .original, exportAspectMode == .fill else { return nil }
        let focusTimeline = reframeFocusPointer()
        let effectiveViewport = zoomEnabled ? viewportTimeline : .identity
        return ReframeTrack.build(
            preset: exportAspect,
            sourceSize: videoSize,
            viewportTimeline: effectiveViewport,
            duration: duration
        ) { editorTime in
            focusTimeline?.location(at: editorTime)
        }
    }

    private func reframeFocusPointer() -> PointerTimeline? {
        if reframeFocusResolved { return reframeFocusTimeline }
        reframeFocusResolved = true
        if pointerIsSynthesized {
            reframeFocusTimeline = pointerTimeline
        } else if !pointerCapture.travel.isEmpty || !pointerCapture.presses.isEmpty {
            reframeFocusTimeline = PointerTimeline.build(
                capture: pointerCapture,
                duration: sourceDuration,
                recordingSizeInPoints: recordingPointSize,
                fallbackArtwork: PointerArtworkCapture.defaultArtwork(),
                clipTimeline: clipTimeline
            )
        }
        return reframeFocusTimeline
    }

    private func rebuildPreviewReframe() {
        guard isLoaded else { return }
        previewReframe = makeReframeTrack()
        motionTimeline = makeMotionTimeline(reframe: previewReframe)
    }


    var basePreviewCanvasSize: CGSize {
        exportAspect == .original
            ? RecordingStudioLayout.originalCanvasSize(
                sourceSize: videoSize, style: style, contentCropRect: videoCropRect
            )
            : exportAspect.canvasSize(for: videoSize)
    }

    var previewCanvasSize: CGSize {
        if exportAspect == .original, isCroppingVideo {
            RecordingStudioLayout.originalCanvasSize(
                sourceSize: videoSize, style: style, contentCropRect: CropGeometry.unit
            )
        } else {
            basePreviewCanvasSize
        }
    }

    var sourceVideoAspect: CGFloat {
        videoSize.height > 0 ? videoSize.width / videoSize.height : 1
    }

    var previewContentAspect: CGFloat? {
        guard videoSize.height > 0 else { return nil }
        return sourceVideoAspect
    }

    var previewVideoCropRect: CGRect {
        isCroppingVideo ? CropGeometry.unit : videoCropRect
    }

    var previewContentMode: RecordingStudioLayout.ContentMode {
        exportAspect == .original || exportAspectMode == .fit ? .fit : .fill
    }

    func previewViewportFrame(at time: TimeInterval) -> ViewportFrame {
        if !isCroppingVideo, let viewport = motionTimeline.viewport(at: time) { return viewport }
        let base = previewReframe?.frame(at: time) ?? viewportFrame(at: time)
        return RecordingVideoCropGeometry.viewport(base, crop: previewVideoCropRect)
    }

    private var freshDeliverableURL: URL? {
        guard ProcessInfo.processInfo.environment["UPSHOT_EXPORT_BYPASS_CACHE"] != "1" else { return nil }
        guard exportDeliveryOptions == RecordingExportDeliveryOptions(), exportAppearance == RecordingExportAppearance(), let session else { return nil }
        return session.freshFinalURL(matching: currentDocument())
    }

    private var exportSuggestedFileName: String {
        let container = exportSettings.effectiveContainer
        if exportDeliveryOptions.format == .gif {
            return sessionURL.deletingPathExtension().lastPathComponent + ".gif"
        }
        return session.map {
            $0.directoryURL
                .deletingPathExtension()
                .lastPathComponent
                .appending(".\(container.fileExtension)")
        } ?? VideoFileActions.exportFileName(for: screenURL, container: container)
    }

    func export(settings: VideoCompressionSettings) {
        exportDeliveryOptions = UpshotPreferences.recordingExtendedExportDefaults
        if settings != exportSettings {
            exportSettings = settings
        }
        export()
    }

    func export() {
        guard !exportState.isExporting, !shareState.isBusy, isLoaded else { return }
        pause()
        let previewURL = sessionURL

        if let cached = freshDeliverableURL {
            let suggestedFileName = exportSuggestedFileName
            exportTask = Task { [weak self] in
                do {
                    let savedURL = try await VideoFileActions.saveToDefaultLocation(
                        from: cached,
                        suggestedFileName: suggestedFileName
                    )
                    RecordingExportNotifier.notifySuccess(fileURL: savedURL)
                    RecordingExportNotifier.revealIfPreferred(fileURL: savedURL)
                    CaptureShelf.shared.dismissVideo(for: previewURL)
                    self?.exportState = .finished(savedURL)
                } catch {
                    self?.exportState = .failed(error.localizedDescription)
                }
            }
            return
        }

        exportState = .exporting(progress: 0)

        let configuration = makeExportConfiguration(includesGIF: true)
        let suggestedFileName = exportSuggestedFileName

        let dockProgressID = DockExportProgressCoordinator.shared.start()

        exportTask = Task { [weak self] in
            do {
                let exporter = RecordingStudioExporter()
                let temporaryURL = try await exporter.export(configuration) { progress in
                    Task { @MainActor [weak self] in
                        DockExportProgressCoordinator.shared.update(dockProgressID, progress: progress)
                        if self?.exportState.isExporting == true {
                            self?.exportState = .exporting(progress: progress)
                        }
                    }
                }
                let savedURL = try await VideoFileActions.saveToDefaultLocation(
                    from: temporaryURL,
                    suggestedFileName: suggestedFileName
                )
                try? FileManager.default.removeItem(at: temporaryURL)
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                RecordingExportNotifier.notifySuccess(fileURL: savedURL)
                RecordingExportNotifier.revealIfPreferred(fileURL: savedURL)
                CaptureShelf.shared.dismissVideo(for: previewURL)
                self?.exportState = .finished(savedURL)
            } catch is CancellationError {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.exportState = .idle
            } catch RecordingStudioExporter.ExportError.cancelled {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.exportState = .idle
            } catch {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.exportState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        if exportState.isExporting {
            exportState = .idle
        }
    }


    var hasAudio: Bool {
        hasRecordedAudio || replacementAudio != nil
    }

    var replacementAudioDrift: TimeInterval? {
        guard let replacementAudio else { return nil }
        let drift = replacementAudio.duration - duration
        return abs(drift) > 0.25 ? drift : nil
    }

    private var audioExportSuggestedFileName: String {
        let base = session.map {
            $0.directoryURL.deletingPathExtension().lastPathComponent
        } ?? screenURL.deletingPathExtension().lastPathComponent
        return "\(base).\(audioExportFormat.fileExtension)"
    }

    func exportAudio() {
        guard !audioExportState.isExporting, isLoaded, hasAudio else { return }
        pause()

        audioExportState = .exporting(progress: 0)

        let configuration = RecordingAudioExporter.Configuration(
            screenURL: screenURL,
            clipTimeline: clipTimeline,
            replacementURL: replacementAudio?.url,
            format: audioExportFormat,
            volume: Double(audioVolume),
            monoAudio: exportDeliveryOptions.monoAudio
        )
        let suggestedFileName = audioExportSuggestedFileName
        let dockProgressID = DockExportProgressCoordinator.shared.start()

        audioExportTask = Task { [weak self] in
            do {
                let temporaryURL = try await RecordingAudioExporter().export(configuration) { progress in
                    Task { @MainActor [weak self] in
                        DockExportProgressCoordinator.shared.update(dockProgressID, progress: progress)
                        if self?.audioExportState.isExporting == true {
                            self?.audioExportState = .exporting(progress: progress)
                        }
                    }
                }
                let savedURL = try await VideoFileActions.saveToDefaultLocation(
                    from: temporaryURL,
                    suggestedFileName: suggestedFileName
                )
                try? FileManager.default.removeItem(at: temporaryURL)
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                RecordingExportNotifier.notifySuccess(fileURL: savedURL)
                RecordingExportNotifier.revealIfPreferred(fileURL: savedURL)
                self?.audioExportState = .finished(savedURL)
            } catch is CancellationError {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.audioExportState = .idle
            } catch {
                DockExportProgressCoordinator.shared.finish(dockProgressID)
                self?.audioExportState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelAudioExport() {
        audioExportTask?.cancel()
        audioExportTask = nil
        if audioExportState.isExporting {
            audioExportState = .idle
        }
    }

    func replaceAudio(with pickedURL: URL) {
        guard isLoaded else { return }
        pause()
        replacementAudioTask?.cancel()

        replacementAudioError = nil
        let displayName = pickedURL.lastPathComponent
        let storedURL: URL
        if let session {
            let destination = session.directoryURL
                .appendingPathComponent(RecordingSession.replacementAudioBaseName)
                .appendingPathExtension(pickedURL.pathExtension.isEmpty ? "m4a" : pickedURL.pathExtension)
            do {
                removeStoredReplacementAudio(in: session)
                try FileManager.default.copyItem(at: pickedURL, to: destination)
            } catch {
                replacementAudioError = "Could not import that file: \(error.localizedDescription)"
                clearReplacementAudio()
                return
            }
            storedURL = destination
        } else {
            storedURL = pickedURL
        }

        replacementAudioTask = Task { [weak self] in
            let resolved = await RecordingReplacementAudio.load(
                url: storedURL,
                displayName: displayName
            )
            guard let self, !Task.isCancelled else { return }
            guard let resolved else {
                if let session = self.session {
                    self.removeStoredReplacementAudio(in: session)
                }
                self.replacementAudioError = "That file has no audio track."
                self.clearReplacementAudio()
                return
            }
            self.replacementAudio = resolved
            self.applyReplacementAudioToPlayback()
        }
    }

    func removeReplacementAudio() {
        guard replacementAudio != nil else { return }
        replacementAudioTask?.cancel()
        replacementAudioTask = nil
        pause()
        if let session {
            removeStoredReplacementAudio(in: session)
        }
        replacementAudioError = nil
        clearReplacementAudio()
    }

    private func clearReplacementAudio() {
        guard replacementAudio != nil else { return }
        replacementAudio = nil
        applyReplacementAudioToPlayback()
    }

    private func applyReplacementAudioToPlayback() {
        do {
            try rebuildScreenPlayerItem(preserving: currentTime)
        } catch {
            loadError = "Could not update the recording timeline: \(error.localizedDescription)"
        }
        scheduleProjectSave()
    }

    private func removeStoredReplacementAudio(in session: RecordingSession) {
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: session.directoryURL.path
        )) ?? []
        for name in names
        where name.hasPrefix("\(RecordingSession.replacementAudioBaseName).") {
            try? FileManager.default.removeItem(
                at: session.directoryURL.appendingPathComponent(name)
            )
        }
    }


    var canShareToCloud: Bool {
        CloudUploader.shared.isConfigured
    }

    func shareToCloud(options: CloudUploadOptions) {
        guard !shareState.isBusy, !exportState.isExporting, isLoaded,
              canShareToCloud else {
            return
        }
        pause()
        projectSaveTask?.cancel()
        writeDraftNow()

        let cachedDeliverable = freshDeliverableURL
        let configuration = cachedDeliverable == nil ? makeExportConfiguration() : nil
        let session = session
        let renderedDocument = session == nil ? nil : currentDocument()
        shareState = cachedDeliverable == nil ? .rendering(progress: 0) : .uploading

        shareTask = Task { [weak self] in
            var temporaryUploadURL: URL?
            defer {
                if let temporaryUploadURL {
                    try? FileManager.default.removeItem(at: temporaryUploadURL)
                }
            }
            do {
                let uploadURL: URL
                if let cachedDeliverable {
                    uploadURL = cachedDeliverable
                } else if let configuration {
                    let dockProgressID = DockExportProgressCoordinator.shared.start()
                    let temporaryURL: URL
                    do {
                        temporaryURL = try await RecordingStudioExporter().export(configuration) { progress in
                            Task { @MainActor [weak self] in
                                DockExportProgressCoordinator.shared.update(dockProgressID, progress: progress)
                                if case .rendering = self?.shareState {
                                    self?.shareState = .rendering(progress: progress)
                                }
                            }
                        }
                        DockExportProgressCoordinator.shared.finish(dockProgressID)
                    } catch {
                        DockExportProgressCoordinator.shared.finish(dockProgressID)
                        throw error
                    }
                    temporaryUploadURL = temporaryURL

                    if let session {
                        uploadURL = try session.installFinalVideo(
                            movingFrom: temporaryURL,
                            renderedFrom: renderedDocument
                        )
                    } else {
                        uploadURL = temporaryURL
                    }
                } else {
                    return
                }

                guard let self, !Task.isCancelled else { return }
                self.shareState = .uploading
                let itemID = self.historyItemID(for: session) ?? UUID()
                self.shareItemID = itemID
                let result = try await CloudUploader.shared.upload(
                    itemID: itemID,
                    fileURL: uploadURL,
                    title: options.trimmedTitleOrNil,
                    socialEnabled: options.socialEnabled
                )

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.url, forType: .string)
                if session != nil {
                    ScreenshotHistoryStore.shared.setCloudURL(for: uploadURL, cloudURL: result.url)
                }
                CaptureShelf.shared.dismissVideo(for: self.sessionURL)
                self.shareState = .finished(result.url)
            } catch is CancellationError {
                self?.shareState = .idle
            } catch RecordingStudioExporter.ExportError.cancelled {
                self?.shareState = .idle
            } catch {
                self?.shareState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelShare() {
        shareTask?.cancel()
        shareTask = nil
        if let shareItemID {
            CloudUploader.shared.cancelUpload(for: shareItemID)
        }
        if shareState.isBusy {
            shareState = .idle
        }
    }

    private func historyItemID(for session: RecordingSession?) -> UUID? {
        guard let session else { return nil }
        let standardizedPath = session.directoryURL.standardizedFileURL.path
        return ScreenshotHistoryStore.shared.items
            .first { $0.recordingSessionPath == standardizedPath }?
            .id
    }
}

struct RecordingZoomTimelineBlock: Identifiable, Equatable, Sendable {
    let cue: ZoomCue
    let editorStart: TimeInterval
    let editorEnd: TimeInterval

    var id: UUID {
        cue.id
    }
}
