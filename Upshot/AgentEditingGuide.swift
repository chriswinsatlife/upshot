//
//  AgentEditingGuide.swift
//  Upshot
//
//  The reference `get_editing_guide` returns. Enum values are read from
//  the types themselves and examples are encoded from real defaults, so the
//  guide can't drift from what the decoders accept.
//

import Foundation

@MainActor
enum AgentEditingGuide {
    static var text: String {
        var sections: [String] = []

        sections.append("""
        # Upshot editing guide

        Times are seconds. Zooms, text, redactions, camera layouts, captions and images are on the \
        source clock (raw recording); audio clips are on the edited clock. Tools convert for you when \
        you pass "clock": "edited". Positions are normalized 0...1 from the top-left; points are \
        [x, y], rects are [[x, y], [width, height]], colors are {red, green, blue, alpha} in 0...1.
        Text and images default to coordinateSpace canvas. Set coordinateSpace recording to follow zoom and pan; position and size then refer to the recorded picture. Arrows default to recording. Redaction rects and zoom points are on the \
        recorded picture (what get_frame shows).
        """)

        sections.append("""
        ## Allowed values
        zoom.anchorMode: \(values(ZoomAnchorMode.self)) (pointerAnchor follows the cursor; pinnedAnchor frames pinnedPoint)
        text.font: \(values(RecordingTextFont.self))
        text.animationIn/animationOut.effect: \(values(RecordingTextAnimation.Effect.self))
        text.animation unit: \(values(RecordingTextAnimation.Unit.self)); order: \(values(RecordingTextAnimation.Order.self)); ease: \(values(RecordingTextAnimation.Ease.self))
        overlay.coordinateSpace: \(values(RecordingOverlayCoordinateSpace.self)); text and image default canvas, arrows default recording
        arrow.direction: \(values(RecordingArrowOverlay.Direction.self)); strokeWidth: integer 1-6, default 4
        redaction.fillColor: null preserves filtering; opaque RGBA replaces source pixels; translucent RGBA tints filtered pixels
        redaction.style: \(values(RecordingRedaction.Style.self))
        camera layout kind: \(values(RecordingCameraLayout.Kind.self))
        camera layout corner: \(values(RecordingCameraLayout.Corner.self)); shape: \(values(RecordingCameraLayout.Shape.self)); side: \(values(RecordingCameraLayout.Side.self)); placement: \(values(RecordingCameraLayout.Placement.self)); screenFit: \(values(RecordingCameraLayout.ScreenFit.self))
        camera layout positionPreset: \(values(RecordingCameraLayout.PositionPreset.self))
        keystrokePlacement / speedBadgePlacement: \(values(RecordingKeystrokePlacement.self))
        exportAspect: \(values(ExportAspectPreset.self))
        exportAspectMode: \(values(ExportAspectContentMode.self))
        style.cursorStyle: \(values(RecordingCursorStyle.self))
        clickEffect: \(values(RecordingClickEffect.self))
        exportSettings.quality: \(values(VideoCompressionQuality.self))
        exportSettings.speed: \(values(VideoCompressionSpeed.self))
        exportSettings.codec: \(values(VideoCompressionCodec.self))
        exportSettings.resolution: \(values(VideoCompressionResolution.self))
        exportSettings.container: \(values(VideoExportContainer.self))
        exportSettings.frameRate: \(values(VideoExportFrameRate.self))
        exportSettings.encodingMode: \(values(VideoExportEncodingMode.self))
        exportSettings.customWidth/customHeight: even integers 2-8192 when resolution is Custom.
        export_video options.gifSize: \(values(RecordingGIFSize.self)); gifLoops: boolean.
        audioExportFormat (export_audio format): \(values(RecordingAudioFormat.self))
        """)

        sections.append("""
        ## Project fields (update_project)
        style: background, padding, cornerRadius, shadow, cursorScale, hidesCursor, cursorStyle, \
        invertsCursor, cameraIsVisible, cameraRoundness, cameraLayout, cameraShrinksDuringZoom, \
        cameraZoomShrinkAmount, cameraZoomResponse, cameraPreviewFrame, cameraFaceLight, cameraSkinSmoothing, cameraPictureCrop.
        cameraLayout.width/height: fractions 0.1-1 of the canvas short side. Circle uses width for both sides; portrait retains 3:4 when height is omitted.
        cameraLayout.positionX/positionY: fractions 0-1 of available space after bubble size and margins. Set positionPreset to custom for custom placement.
        cameraPreviewFrame: standard draws an inward glass rim; softBlur feathers 16 reference pixels at a 1920-pixel canvas width. Legacy retains the old border.
        cameraZoomResponse: magnification uses 1 - cameraZoomShrinkAmount * (1 - 1 / magnification). A shrink amount of 0.7 gives scale 0.65 at 2×. Progress retains the old zoom-progress response.
        cameraPictureCrop: normalized source rectangle [[x, y], [width, height]], minimum side 0.08; omitted means full picture.
        Camera source: set_camera_source copies and loops a camera video from zero. Omit path to remove the camera.
        cameraSource: null uses the recorded sidecar; {kind: "removed"} removes the camera; uploaded sources use {kind: "uploaded", fileName, displayName} under the project's media directory.
        Cursor motion in style: cursorSmoothing (0-2, null preserves the existing spring), \
        cursorSpringStiffnessMultiplier, cursorSpringDampingMultiplier, cursorSpringMassMultiplier (0.25-3 each).
        Cursor bounce in style: cursorClickBounce (0-5, null preserves the existing click pulse), cursorClickBounceDuration (0.06-0.5 seconds).
        update_project accepts motionPreset: Focused or Cinematic to apply zoom timing and cursor motion together.
        update_project also accepts appearance: {zoomMotion: {zoomInDuration, zoomOutDuration, connectZooms, connectedZoomGap, connectedZoomDuration}} beside patch.
        Zoom durations use seconds: entry and exit 0.06-4, connection gap 0-5 with eligibility capped at 1.5, connected pan 0.06-4.
        A null zoomMotion retains legacy Smooth or Dynamic animation. Custom motion values persist on reopen.
        Click effects: clickEffect, clickEffectColor (#RGB or #RRGGBB), clickEffectScale (0.5-2), \
        clickEffectOpacity (0-1), clickEffectDuration (0.12-1.2 seconds). Impact preserves the existing blue highlight. \
        Selecting spotlight, ripple, echo, or burst resets color to #9CA3AF unless clickEffectColor is supplied. \
        showsClickEffects controls visibility for every clickEffect.
        Toggles: zoomEnabled, showsClickEffects, showsKeystrokes, showsSpeedBadge, showsSubtitles, \
        subtitleWordHighlight. Subtitle look: subtitleVerticalPosition (0.1-0.95), subtitleFontScale (0.6-1.8).
        Output: exportAspect, exportAspectMode, exportCustomAspectWidth/exportCustomAspectHeight (integers 128-7680, used when exportAspect is custom), videoCropRect (normalized crop of the recording), \
        audioVolume (0-2), exportSettings.
        clips: the ordered list of {sourceStart, sourceEnd, speed} that makes up the edited movie. \
        Replacing it with one clip covering the whole recording undoes every cut.
        """)

        sections.append("## Item defaults (fields you may set)\n" + examples())
        sections.append("## Backgrounds (set style.background to one of these)\n" + backgrounds())
        return sections.joined(separator: "\n\n")
    }

    private static func values<T: CaseIterable & RawRepresentable>(_ type: T.Type) -> String where T.RawValue == String {
        T.allCases.map(\.rawValue).joined(separator: ", ")
    }

    private static func examples() -> String {
        func line(_ label: String, _ value: some Encodable) -> String {
            guard var json = try? JSONValue(encoding: value) else { return "" }
            json = json.merging(["id": .null])
            return "\(label): \(json.compactString)"
        }
        return [
            line("zoom", ZoomCue(start: 0, end: 3)),
            line("text", RecordingTextOverlay(start: 0, end: 3)),
            line("redaction", RecordingRedaction(start: 0, end: 3)),
            line("arrow", RecordingArrowOverlay(start: 0, end: 3)),
            line("camera_layout", RecordingCameraLayoutCue(start: 0, end: 3, layout: RecordingCameraLayout())),
            line("caption", RecordingSubtitleCue(start: 0, end: 3, text: "Hello")),
            line("exportSettings", VideoCompressionSettings()),
        ].joined(separator: "\n")
    }

    private static func backgrounds() -> String {
        var options: [String] = []
        if let none = try? JSONValue(encoding: StoredBackgroundStyle.none) {
            options.append("none: \(none.compactString)")
        }
        let solid = StoredBackgroundStyle.solid(StoredColor(
            AnnotationBackgroundColor("custom", title: "Custom", red: 0.08, green: 0.09, blue: 0.12)
        ))
        if let json = try? JSONValue(encoding: solid) {
            options.append("solid (any RGB): \(json.compactString)")
        }
        for gradient in AnnotationBackgroundGradient.presets {
            if let json = try? JSONValue(encoding: StoredBackgroundStyle.gradient(StoredGradient(gradient))) {
                options.append("\(gradient.title): \(json.compactString)")
            }
        }
        if let json = try? JSONValue(encoding: StoredBackgroundStyle.customWallpaper(path: "<absolute path to an image or movie>")) {
            options.append("wallpaper (image or looping video, sampled on the edited clock): \(json.compactString)")
        }
        return options.joined(separator: "\n")
    }
}

extension JSONValue {
    nonisolated var compactString: String {
        guard let data = try? JSONValue.encoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}
