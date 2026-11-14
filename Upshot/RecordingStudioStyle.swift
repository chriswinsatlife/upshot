import CoreGraphics
import Foundation

nonisolated struct RecordingCameraBubbleSettings: Equatable {
    var isVisible = true

    var roundness: CGFloat = 0.25

    var layout = RecordingCameraLayout()

    var shrinksDuringZoom = true

    var zoomShrinkAmount: CGFloat = RecordingCameraBubbleSettings.defaultZoomShrinkAmount

    var beauty = StudioCameraBeauty()

    static let defaultZoomShrinkAmount: CGFloat = 0.1
    static let zoomShrinkAmountRange: ClosedRange<CGFloat> = 0.05...0.4
}

nonisolated struct RecordingEditDocument: Codable, Equatable {
    var formatVersion = 5
    var style: StoredRecordingStudioStyle
    var zoomEnabled: Bool
    var zoomCues: [ZoomCue]

    var cameraLayoutCues: [RecordingCameraLayoutCue]?

    var textOverlays: [RecordingTextOverlay]?
    var redactions: [RecordingRedaction]?

    var imageOverlays: [RecordingImageOverlay]?
    var audioClips: [RecordingAudioClip]?

    var clips: [RecordingClipSegment]?
    var trimStart: TimeInterval?
    var trimEnd: TimeInterval?
    var exportSettings: VideoCompressionSettings?

    var showsClickEffects: Bool?
    var showsKeystrokes: Bool?
    var keystrokePlacement: RecordingKeystrokePlacement?

    var showsSpeedBadge: Bool?
    var speedBadgePlacement: RecordingKeystrokePlacement?

    var showsSubtitles: Bool?
    var subtitleCues: [RecordingSubtitleCue]?

    var subtitleWords: [RecordingTranscriptWord]?
    var subtitleVerticalPosition: Double?
    var subtitleFontScale: Double?
    var subtitleWordHighlight: Bool?

    var exportAspect: String?

    var exportAspectMode: String?

    var videoCropRect: CGRect?

    var replacementAudioFileName: String?

    var replacementAudioDisplayName: String?

    var audioExportFormat: String?
    var audioVolume: Double?

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case style
        case zoomEnabled
        case zoomCues
        case cameraLayoutCues
        case textOverlays
        case redactions
        case imageOverlays
        case audioClips
        case clips
        case trimStart
        case trimEnd
        case exportSettings
        case showsClickEffects
        case showsKeystrokes
        case keystrokePlacement
        case showsSpeedBadge
        case speedBadgePlacement
        case showsSubtitles
        case subtitleCues
        case subtitleWords
        case subtitleVerticalPosition
        case subtitleFontScale
        case subtitleWordHighlight
        case exportAspect
        case exportAspectMode
        case videoCropRect

        case canvasCropRect
        case replacementAudioFileName
        case replacementAudioDisplayName
        case audioExportFormat
        case audioVolume
    }

    init(
        style: RecordingStudioStyle,
        zoomEnabled: Bool,
        zoomCues: [ZoomCue],
        cameraLayoutCues: [RecordingCameraLayoutCue]? = nil,
        textOverlays: [RecordingTextOverlay]? = nil,
        redactions: [RecordingRedaction]? = nil,
        imageOverlays: [RecordingImageOverlay]? = nil,
        audioClips: [RecordingAudioClip]? = nil,
        clipTimeline: RecordingClipTimeline? = nil,
        trimSelection: VideoTrimSelection? = nil,
        exportSettings: VideoCompressionSettings? = nil,
        showsClickEffects: Bool? = nil,
        showsKeystrokes: Bool? = nil,
        keystrokePlacement: RecordingKeystrokePlacement? = nil,
        showsSpeedBadge: Bool? = nil,
        speedBadgePlacement: RecordingKeystrokePlacement? = nil,
        showsSubtitles: Bool? = nil,
        subtitleCues: [RecordingSubtitleCue]? = nil,
        subtitleWords: [RecordingTranscriptWord]? = nil,
        subtitleStyle: SubtitleBarStyle? = nil,
        exportAspect: ExportAspectPreset? = nil,
        exportAspectMode: ExportAspectContentMode? = nil,
        videoCropRect: CGRect? = nil,
        replacementAudioFileName: String? = nil,
        replacementAudioDisplayName: String? = nil,
        audioExportFormat: RecordingAudioFormat? = nil,
        audioVolume: Double? = nil
    ) {
        self.style = StoredRecordingStudioStyle(style)
        self.zoomEnabled = zoomEnabled
        self.zoomCues = zoomCues
        self.cameraLayoutCues = cameraLayoutCues
        self.textOverlays = textOverlays
        self.redactions = redactions
        self.imageOverlays = imageOverlays
        self.audioClips = audioClips
        clips = clipTimeline?.segments
        if let clip = clipTimeline?.segments.only {

            trimStart = clip.sourceStart
            trimEnd = clip.sourceEnd
        } else {
            trimStart = trimSelection?.start
            trimEnd = trimSelection?.end
        }
        self.exportSettings = exportSettings
        self.showsClickEffects = showsClickEffects
        self.showsKeystrokes = showsKeystrokes
        self.keystrokePlacement = keystrokePlacement
        self.showsSpeedBadge = showsSpeedBadge
        self.speedBadgePlacement = speedBadgePlacement
        self.showsSubtitles = showsSubtitles
        self.subtitleCues = subtitleCues
        self.subtitleWords = subtitleWords
        subtitleVerticalPosition = subtitleStyle?.verticalPosition
        subtitleFontScale = subtitleStyle?.fontScale
        subtitleWordHighlight = subtitleStyle?.highlightsSpokenWord
        self.exportAspect = exportAspect.map(\.rawValue)
        self.exportAspectMode = exportAspectMode.map(\.rawValue)
        self.videoCropRect = videoCropRect
        self.replacementAudioFileName = replacementAudioFileName
        self.replacementAudioDisplayName = replacementAudioDisplayName
        self.audioExportFormat = audioExportFormat.map(\.rawValue)
        self.audioVolume = audioVolume
    }

    var audioExportFormatValue: RecordingAudioFormat {
        audioExportFormat.flatMap(RecordingAudioFormat.init(rawValue:)) ?? .m4a
    }

    var subtitleStyle: SubtitleBarStyle {
        var style = SubtitleBarStyle()
        if let subtitleVerticalPosition {
            style.verticalPosition = subtitleVerticalPosition
        }
        if let subtitleFontScale {
            style.fontScale = subtitleFontScale
        }
        if let subtitleWordHighlight {
            style.highlightsSpokenWord = subtitleWordHighlight
        }
        return style
    }

    var exportAspectPreset: ExportAspectPreset {
        exportAspect.flatMap(ExportAspectPreset.init(rawValue:)) ?? .original
    }

    var exportAspectContentMode: ExportAspectContentMode {
        exportAspectMode.flatMap(ExportAspectContentMode.init(rawValue:)) ?? .fill
    }

    var normalizedVideoCropRect: CGRect {
        guard let videoCropRect else { return CropGeometry.unit }
        let crop = videoCropRect.standardized.intersection(CropGeometry.unit)
        guard crop.width > 0.0001, crop.height > 0.0001 else {
            return CropGeometry.unit
        }
        return crop
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        style = try container.decode(StoredRecordingStudioStyle.self, forKey: .style)
        zoomEnabled = try container.decodeIfPresent(Bool.self, forKey: .zoomEnabled) ?? true
        zoomCues = try container.decodeIfPresent([ZoomCue].self, forKey: .zoomCues) ?? []
        cameraLayoutCues = try container.decodeIfPresent(
            [RecordingCameraLayoutCue].self,
            forKey: .cameraLayoutCues
        )
        textOverlays = try container.decodeIfPresent([RecordingTextOverlay].self, forKey: .textOverlays)
        redactions = try container.decodeIfPresent([RecordingRedaction].self, forKey: .redactions)
        imageOverlays = try container.decodeIfPresent([RecordingImageOverlay].self, forKey: .imageOverlays)
        audioClips = try container.decodeIfPresent([RecordingAudioClip].self, forKey: .audioClips)
        clips = try container.decodeIfPresent([RecordingClipSegment].self, forKey: .clips)
        trimStart = try container.decodeIfPresent(TimeInterval.self, forKey: .trimStart)
        trimEnd = try container.decodeIfPresent(TimeInterval.self, forKey: .trimEnd)
        exportSettings = try container.decodeIfPresent(
            VideoCompressionSettings.self,
            forKey: .exportSettings
        )
        showsClickEffects = try container.decodeIfPresent(Bool.self, forKey: .showsClickEffects)
        showsKeystrokes = try container.decodeIfPresent(Bool.self, forKey: .showsKeystrokes)
        keystrokePlacement = try container.decodeIfPresent(
            RecordingKeystrokePlacement.self,
            forKey: .keystrokePlacement
        )
        showsSpeedBadge = try container.decodeIfPresent(Bool.self, forKey: .showsSpeedBadge)
        speedBadgePlacement = try container.decodeIfPresent(
            RecordingKeystrokePlacement.self,
            forKey: .speedBadgePlacement
        )
        showsSubtitles = try container.decodeIfPresent(Bool.self, forKey: .showsSubtitles)
        subtitleCues = try container.decodeIfPresent(
            [RecordingSubtitleCue].self,
            forKey: .subtitleCues
        )
        subtitleWords = try container.decodeIfPresent(
            [RecordingTranscriptWord].self,
            forKey: .subtitleWords
        )
        subtitleVerticalPosition = try container.decodeIfPresent(
            Double.self,
            forKey: .subtitleVerticalPosition
        )
        subtitleFontScale = try container.decodeIfPresent(Double.self, forKey: .subtitleFontScale)
        subtitleWordHighlight = try container.decodeIfPresent(Bool.self, forKey: .subtitleWordHighlight)
        exportAspect = try container.decodeIfPresent(String.self, forKey: .exportAspect)
        exportAspectMode = try container.decodeIfPresent(String.self, forKey: .exportAspectMode)
        videoCropRect = try container.decodeIfPresent(CGRect.self, forKey: .videoCropRect)
            ?? container.decodeIfPresent(CGRect.self, forKey: .canvasCropRect)
        replacementAudioFileName = try container.decodeIfPresent(
            String.self,
            forKey: .replacementAudioFileName
        )
        replacementAudioDisplayName = try container.decodeIfPresent(
            String.self,
            forKey: .replacementAudioDisplayName
        )
        audioExportFormat = try container.decodeIfPresent(String.self, forKey: .audioExportFormat)
        audioVolume = try container.decodeIfPresent(Double.self, forKey: .audioVolume)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(style, forKey: .style)
        try container.encode(zoomEnabled, forKey: .zoomEnabled)
        try container.encode(zoomCues, forKey: .zoomCues)
        try container.encodeIfPresent(cameraLayoutCues, forKey: .cameraLayoutCues)
        try container.encodeIfPresent(textOverlays, forKey: .textOverlays)
        try container.encodeIfPresent(redactions, forKey: .redactions)
        try container.encodeIfPresent(imageOverlays, forKey: .imageOverlays)
        try container.encodeIfPresent(audioClips, forKey: .audioClips)
        try container.encodeIfPresent(clips, forKey: .clips)
        try container.encodeIfPresent(trimStart, forKey: .trimStart)
        try container.encodeIfPresent(trimEnd, forKey: .trimEnd)
        try container.encodeIfPresent(exportSettings, forKey: .exportSettings)
        try container.encodeIfPresent(showsClickEffects, forKey: .showsClickEffects)
        try container.encodeIfPresent(showsKeystrokes, forKey: .showsKeystrokes)
        try container.encodeIfPresent(keystrokePlacement, forKey: .keystrokePlacement)
        try container.encodeIfPresent(showsSpeedBadge, forKey: .showsSpeedBadge)
        try container.encodeIfPresent(speedBadgePlacement, forKey: .speedBadgePlacement)
        try container.encodeIfPresent(showsSubtitles, forKey: .showsSubtitles)
        try container.encodeIfPresent(subtitleCues, forKey: .subtitleCues)
        try container.encodeIfPresent(subtitleWords, forKey: .subtitleWords)
        try container.encodeIfPresent(subtitleVerticalPosition, forKey: .subtitleVerticalPosition)
        try container.encodeIfPresent(subtitleFontScale, forKey: .subtitleFontScale)
        try container.encodeIfPresent(subtitleWordHighlight, forKey: .subtitleWordHighlight)
        try container.encodeIfPresent(exportAspect, forKey: .exportAspect)
        try container.encodeIfPresent(exportAspectMode, forKey: .exportAspectMode)
        try container.encodeIfPresent(videoCropRect, forKey: .videoCropRect)
        try container.encodeIfPresent(replacementAudioFileName, forKey: .replacementAudioFileName)
        try container.encodeIfPresent(
            replacementAudioDisplayName,
            forKey: .replacementAudioDisplayName
        )
        try container.encodeIfPresent(audioExportFormat, forKey: .audioExportFormat)
        try container.encodeIfPresent(audioVolume, forKey: .audioVolume)
    }
}

private extension Array {
    nonisolated var only: Element? {
        count == 1 ? first : nil
    }
}

nonisolated struct StoredRecordingStudioStyle: Codable, Equatable {
    var background: StoredBackgroundStyle
    var padding: Double
    var cornerRadius: Double
    var shadow: Double

    var cursorScale: Double?
    var hidesCursor: Bool?

    var cursorStyle: RecordingCursorStyle?

    var invertsCursor: Bool?
    var cameraIsVisible: Bool
    var cameraCenterX: Double
    var cameraCenterY: Double
    var cameraSize: Double
    var cameraRoundness: Double

    var cameraLayout: RecordingCameraLayout?

    var cameraShrinksDuringZoom: Bool?
    var cameraZoomShrinkAmount: Double?

    var cameraFaceLight: Double?
    var cameraSkinSmoothing: Double?

    init(_ style: RecordingStudioStyle) {
        switch style.background {
        case .none:
            background = .none
        case .solid(let color):
            background = .solid(StoredColor(color))
        case .gradient(let gradient):
            background = .gradient(StoredGradient(gradient))
        case .customWallpaper(let wallpaper):
            background = .customWallpaper(path: wallpaper.url.path)
        }
        padding = Double(style.padding)
        cornerRadius = Double(style.cornerRadius)
        shadow = Double(style.shadow)
        cursorScale = Double(style.cursorScale)
        hidesCursor = style.hidesCursor ? true : nil
        cursorStyle = style.cursorStyle == .system ? nil : style.cursorStyle
        invertsCursor = style.invertsCursor ? true : nil
        cameraIsVisible = style.camera.isVisible
        let legacyCenter = style.camera.layout.legacyCenter
        cameraCenterX = Double(legacyCenter.x)
        cameraCenterY = Double(legacyCenter.y)
        cameraSize = style.camera.layout.size
        cameraRoundness = Double(style.camera.roundness)
        cameraLayout = style.camera.layout
        cameraShrinksDuringZoom = style.camera.shrinksDuringZoom ? nil : false
        cameraZoomShrinkAmount = style.camera.zoomShrinkAmount == RecordingCameraBubbleSettings.defaultZoomShrinkAmount
            ? nil
            : Double(style.camera.zoomShrinkAmount)
        cameraFaceLight = style.camera.beauty.faceLight > 0 ? Double(style.camera.beauty.faceLight) : nil
        cameraSkinSmoothing = style.camera.beauty.skinSmoothing > 0 ? Double(style.camera.beauty.skinSmoothing) : nil
    }

    var value: RecordingStudioStyle {
        let backgroundValue: AnnotationBackgroundStyle
        switch background {
        case .none:
            backgroundValue = .none
        case .solid(let color):
            backgroundValue = .solid(color.backgroundColor)
        case .gradient(let gradient):
            backgroundValue = .gradient(gradient.backgroundGradient)
        case .customWallpaper(let path):
            backgroundValue = .customWallpaper(AnnotationCustomWallpaper(url: URL(fileURLWithPath: path)))
        }

        return RecordingStudioStyle(
            background: backgroundValue,
            padding: CGFloat(padding),
            cornerRadius: CGFloat(cornerRadius),
            shadow: CGFloat(shadow),
            cursorScale: CGFloat(cursorScale ?? RecordingStudioStyle.defaultCursorScale),
            hidesCursor: hidesCursor ?? false,
            cursorStyle: cursorStyle ?? .system,
            invertsCursor: invertsCursor ?? false,
            camera: RecordingCameraBubbleSettings(
                isVisible: cameraIsVisible,

                roundness: CGFloat(cameraLayout == nil && cameraRoundness >= 0.49 ? 0.25 : cameraRoundness),
                layout: cameraLayout ?? .migrated(
                    center: CGPoint(x: cameraCenterX, y: cameraCenterY),
                    size: cameraSize,
                    roundness: cameraRoundness
                ),
                shrinksDuringZoom: cameraShrinksDuringZoom ?? true,
                zoomShrinkAmount: cameraZoomShrinkAmount.map {
                    min(max(CGFloat($0), RecordingCameraBubbleSettings.zoomShrinkAmountRange.lowerBound),
                        RecordingCameraBubbleSettings.zoomShrinkAmountRange.upperBound)
                } ?? RecordingCameraBubbleSettings.defaultZoomShrinkAmount,
                beauty: StudioCameraBeauty(
                    faceLight: CGFloat(min(max(cameraFaceLight ?? 0, 0), 1)),
                    skinSmoothing: CGFloat(min(max(cameraSkinSmoothing ?? 0, 0), 1))
                )
            )
        )
    }
}

nonisolated struct RecordingStudioStyle: Equatable {
    static let defaultCursorScale: CGFloat = 1.7

    static var defaultBackground: AnnotationBackgroundStyle {
        guard let gradient = AnnotationBackgroundGradient.presets.last else { return .none }
        return .gradient(gradient)
    }

    var background: AnnotationBackgroundStyle = RecordingStudioStyle.defaultBackground

    var padding: CGFloat = 0.06

    var cornerRadius: CGFloat = 0.02

    var shadow: CGFloat = 0.45

    var cursorScale: CGFloat = RecordingStudioStyle.defaultCursorScale
    var hidesCursor = false
    var cursorStyle = RecordingCursorStyle.system

    var invertsCursor = false
    var camera = RecordingCameraBubbleSettings()
}

enum RecordingStudioDefaults {
    private static let backgroundKey = "recordingStudio.lastUsedBackground.v1"

    static var background: AnnotationBackgroundStyle {
        get {
            guard let data = UpshotStorage.defaults.data(forKey: backgroundKey),
                  let stored = try? JSONDecoder().decode(StoredBackgroundStyle.self, from: data) else {
                return RecordingStudioStyle.defaultBackground
            }
            return backgroundStyle(from: stored)
        }
        set {
            let stored = storedBackgroundStyle(from: newValue)
            guard let data = try? JSONEncoder().encode(stored) else { return }
            UpshotStorage.defaults.set(data, forKey: backgroundKey)
        }
    }

    private static func storedBackgroundStyle(
        from style: AnnotationBackgroundStyle
    ) -> StoredBackgroundStyle {
        switch style {
        case .none:
            .none
        case .solid(let color):
            .solid(StoredColor(color))
        case .gradient(let gradient):
            .gradient(StoredGradient(gradient))
        case .customWallpaper(let wallpaper):
            .customWallpaper(path: wallpaper.url.path)
        }
    }

    private static func backgroundStyle(
        from stored: StoredBackgroundStyle
    ) -> AnnotationBackgroundStyle {
        switch stored {
        case .none:
            .none
        case .solid(let color):
            .solid(color.backgroundColor)
        case .gradient(let gradient):
            .gradient(gradient.backgroundGradient)
        case .customWallpaper(let path):
            .customWallpaper(AnnotationCustomWallpaper(url: URL(fileURLWithPath: path)))
        }
    }
}

nonisolated struct RecordingStudioLayout: Sendable, Equatable {

    static func originalCanvasSize(
        sourceSize: CGSize,
        style: RecordingStudioStyle,
        contentCropRect: CGRect
    ) -> CGSize {
        let crop = RecordingVideoCropGeometry.isCropped(contentCropRect)
            ? RecordingVideoCropGeometry.normalized(contentCropRect)
            : RecordingVideoCropGeometry.unit
        let visibleSize = CGSize(
            width: sourceSize.width * crop.width,
            height: sourceSize.height * crop.height
        )
        let padding = min(max(style.padding, 0), 0.475)
        let inset = min(visibleSize.width, visibleSize.height) * padding / (1 - 2 * padding)
        return CGSize(width: visibleSize.width + 2 * inset, height: visibleSize.height + 2 * inset)
    }

    let canvasSize: CGSize
    let cardRect: CGRect
    let cardCornerRadius: CGFloat
    let bubbleRect: CGRect
    let bubbleCornerRadius: CGFloat

    let contentFillSize: CGSize

    var contentCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var screenOpacity: CGFloat = 1
    var cameraOpacity: CGFloat = 1

    var cameraCutout: CGFloat = 0

    enum ContentMode: Sendable {

        case fill

        case fit
    }

    static func bubbleMargin(forMinDimension minDimension: CGFloat) -> CGFloat {
        (minDimension * 0.03).rounded()
    }

    static func make(
        canvasSize: CGSize,
        style: RecordingStudioStyle,
        usesUniformPadding: Bool = false,
        contentAspect: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        contentCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    ) -> RecordingStudioLayout {
        let minDimension = min(canvasSize.width, canvasSize.height)
        let inset = usesUniformPadding
            ? min(max(style.padding, 0), 0.475) * minDimension
            : (style.padding * minDimension).rounded()

        let cardScale = max(0.05, 1 - 2 * inset / minDimension)
        var cardSize = usesUniformPadding ? CGSize(
            width: canvasSize.width - 2 * inset,
            height: canvasSize.height - 2 * inset
        ) : CGSize(
            width: (canvasSize.width * cardScale).rounded(),
            height: (canvasSize.height * cardScale).rounded()
        )
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalizedCrop = contentCropRect.standardized.intersection(unit)
        let crop = normalizedCrop.width > 0.0001 && normalizedCrop.height > 0.0001
            ? normalizedCrop
            : unit
        let hasContentCrop = crop.minX > 0.0005
            || crop.minY > 0.0005
            || crop.width < 0.999
            || crop.height < 0.999
        let sourceAspect = contentAspect ?? (canvasSize.height > 0 ? canvasSize.width / canvasSize.height : 1)
        let cardAspect: CGFloat? = if hasContentCrop {
            sourceAspect * crop.width / crop.height
        } else if case .fit = contentMode {
            contentAspect
        } else {
            nil
        }
        if let cardAspect, cardAspect > 0, !usesUniformPadding {

            let fitHeight = min(cardSize.height, cardSize.width / cardAspect)
            cardSize = CGSize(
                width: (cardAspect * fitHeight).rounded(),
                height: fitHeight.rounded()
            )
        }
        let cardRect = CGRect(
            x: usesUniformPadding ? (canvasSize.width - cardSize.width) / 2
                : ((canvasSize.width - cardSize.width) / 2).rounded(),
            y: usesUniformPadding ? (canvasSize.height - cardSize.height) / 2
                : ((canvasSize.height - cardSize.height) / 2).rounded(),
            width: cardSize.width,
            height: cardSize.height
        )
        let cardCornerRadius = style.cornerRadius * minDimension

        var contentFillSize = cardRect.size
        if hasContentCrop {

            let fillHeight = max(
                cardRect.height / crop.height,
                cardRect.width / (crop.width * sourceAspect)
            )
            contentFillSize = CGSize(width: sourceAspect * fillHeight, height: fillHeight)
        } else if let contentAspect, contentAspect > 0, cardRect.height > 0 {
            let fillHeight = max(cardRect.height, cardRect.width / contentAspect)
            contentFillSize = CGSize(
                width: contentAspect * fillHeight,
                height: fillHeight
            )
        }

        return RecordingStudioLayout(
            canvasSize: canvasSize,
            cardRect: cardRect,
            cardCornerRadius: cardCornerRadius,
            bubbleRect: .zero,
            bubbleCornerRadius: 0,
            contentFillSize: contentFillSize,
            contentCropRect: crop,
            cameraOpacity: 0
        )
    }

    func frameRect(for viewport: ViewportFrame) -> CGRect {
        let drawWidth = contentFillSize.width * viewport.magnification
        let drawHeight = contentFillSize.height * viewport.magnification
        return CGRect(
            x: cardRect.midX - viewport.anchor.x * drawWidth,
            y: cardRect.midY - viewport.anchor.y * drawHeight,
            width: drawWidth,
            height: drawHeight
        )
    }
}

nonisolated enum RecordingVideoCropGeometry {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func normalized(_ requested: CGRect) -> CGRect {
        let crop = requested.standardized.intersection(unit)
        guard crop.width > 0.0001, crop.height > 0.0001 else { return unit }
        return crop
    }

    static func isCropped(_ requested: CGRect) -> Bool {
        let crop = normalized(requested)
        return crop.minX > 0.0005
            || crop.minY > 0.0005
            || crop.width < 0.999
            || crop.height < 0.999
    }

    static func viewport(_ base: ViewportFrame, crop requested: CGRect) -> ViewportFrame {
        let crop = normalized(requested)
        guard isCropped(crop) else { return base }

        let magnification = max(base.magnification, 1)
        let center = CGPoint(x: crop.midX, y: crop.midY)
        let halfWidth = crop.width / CGFloat(2 * magnification)
        let halfHeight = crop.height / CGFloat(2 * magnification)
        let target = CGPoint(
            x: min(max(base.anchor.x, crop.minX + halfWidth), crop.maxX - halfWidth),
            y: min(max(base.anchor.y, crop.minY + halfHeight), crop.maxY - halfHeight)
        )

        let progress = CGFloat(min(max((magnification - 1) / 0.12, 0), 1))
        return ViewportFrame(
            magnification: magnification,
            anchor: CGPoint(
                x: center.x + (target.x - center.x) * progress,
                y: center.y + (target.y - center.y) * progress
            )
        )
    }
}
