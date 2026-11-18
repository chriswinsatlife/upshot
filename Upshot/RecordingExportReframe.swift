//
//  RecordingExportReframe.swift
//  Upshot
//
//  Export-time reframing: renders the recording into a different aspect
//  ratio (Shorts, square, portrait) by cropping into the source with a
//  virtual camera that follows the action. The result is an ordinary
//  frame track consumed by the exporter's compositor, so motion blur,
//  the synthetic pointer, and captions all come along for free.
//
//  The reframe camera is deliberately calm: the pointer only drags the
//  crop when it leaves a generous dead zone, moves are low-passed, and
//  during zoom cues the crop defers to the zoom's own (already smoothed)
//  anchor so the two cameras never fight.
//

import CoreGraphics
import Foundation

/// Output aspect choices shown in the Studio's export section.
nonisolated enum ExportAspectPreset: String, Codable, CaseIterable, Sendable {
    case original
    case wide16x9
    case vertical9x16
    case square
    case portrait4x5
    case landscape3x2
    case landscape4x3
    case landscape5x4
    case portrait3x4
    case portrait2x3
    case wide16x10
    case vertical10x16
    case wide3x1
    case custom

    var title: String {
        switch self {
        case .original: "Original"
        case .wide16x9: "16:9"
        case .vertical9x16: "9:16"
        case .square: "1:1"
        case .portrait4x5: "4:5"
        case .landscape3x2: "3:2"
        case .landscape4x3: "4:3"
        case .landscape5x4: "5:4"
        case .portrait3x4: "3:4"
        case .portrait2x3: "2:3"
        case .wide16x10: "16:10"
        case .vertical10x16: "10:16"
        case .wide3x1: "3:1"
        case .custom: "Custom"
        }
    }

    var help: String {
        switch self {
        case .original: "Keep the recording's own aspect ratio"
        case .wide16x9: "Landscape 16:9 - YouTube"
        case .vertical9x16: "Vertical 9:16 - Shorts, Reels, TikTok"
        case .square: "Square 1:1"
        case .portrait4x5: "Portrait 4:5 - feed posts"
        case .landscape3x2, .landscape4x3, .landscape5x4, .wide16x10, .wide3x1:
            "Landscape \(title)"
        case .portrait3x4, .portrait2x3, .vertical10x16:
            "Portrait \(title)"
        case .custom: "Use a custom width-to-height ratio"
        }
    }

    /// Width divided by height; nil means "keep the source".
    var ratio: CGFloat? {
        switch self {
        case .original, .custom: nil
        case .wide16x9: 16.0 / 9.0
        case .vertical9x16: 9.0 / 16.0
        case .square: 1
        case .portrait4x5: 4.0 / 5.0
        case .landscape3x2: 3.0 / 2.0
        case .landscape4x3: 4.0 / 3.0
        case .landscape5x4: 5.0 / 4.0
        case .portrait3x4: 3.0 / 4.0
        case .portrait2x3: 2.0 / 3.0
        case .wide16x10: 16.0 / 10.0
        case .vertical10x16: 10.0 / 16.0
        case .wide3x1: 3
        }
    }

    /// Canvas for this preset derived from the source, preserving the
    /// source's pixel density along the surviving axis.
    func resolvedRatio(customWidth: Int = 1920, customHeight: Int = 1080) -> CGFloat? {
        guard self == .custom else { return ratio }
        guard (128...7680).contains(customWidth), (128...7680).contains(customHeight) else {
            return 16.0 / 9.0
        }
        return CGFloat(customWidth) / CGFloat(customHeight)
    }

    func canvasSize(for source: CGSize, customWidth: Int = 1920, customHeight: Int = 1080) -> CGSize {
        guard let ratio = resolvedRatio(customWidth: customWidth, customHeight: customHeight),
              source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0 else { return source }
        let bounds: CGSize
        switch self {
        case .landscape3x2, .landscape4x3, .landscape5x4, .portrait3x4,
             .portrait2x3, .wide16x10, .vertical10x16, .wide3x1, .custom:
            let longSide = max(source.width, source.height)
            let shortSide = min(source.width, source.height)
            bounds = ratio >= 1
                ? CGSize(width: longSide, height: shortSide)
                : CGSize(width: shortSide, height: longSide)
        case .original, .wide16x9, .vertical9x16, .square, .portrait4x5:
            bounds = source
        }
        let sourceRatio = bounds.width / bounds.height
        var size: CGSize
        if ratio < sourceRatio {
            size = CGSize(width: bounds.height * ratio, height: bounds.height)
        } else {
            size = CGSize(width: bounds.width, height: bounds.width / ratio)
        }
        size.width = CGFloat(max(2, Int(size.width.rounded()) & ~1))
        size.height = CGFloat(max(2, Int(size.height.rounded()) & ~1))
        return size
    }
}

/// How the recording occupies a non-original aspect canvas: cropped to
/// fill it with a follow camera, or fitted whole with the background
/// styling filling the rest.
nonisolated enum ExportAspectContentMode: String, Codable, CaseIterable, Sendable {
    case fill
    case fit

    var title: String {
        switch self {
        case .fill: "Fill"
        case .fit: "Fit"
        }
    }

    var help: String {
        switch self {
        case .fill: "Crop into the recording; the camera follows your cursor and zooms"
        case .fit: "Show the full recording framed on the background"
        }
    }
}

/// The synthesized reframe camera: viewport frames on the editor timeline,
/// sampled at the same cadence as ViewportTimeline.
nonisolated struct ReframeTrack: Sendable {
    static let stepRate: Double = 120

    let preset: ExportAspectPreset
    /// Source video aspect (width / height); the compositor uses this to
    /// aspect-fill the card instead of stretching into it.
    let sourceAspect: CGFloat
    private let frames: [ViewportFrame]
    private let duration: TimeInterval

    func frame(at time: TimeInterval) -> ViewportFrame {
        guard frames.count > 1, duration > 0 else { return frames.first ?? .identity }
        let position = min(max(time, 0), duration) * Self.stepRate
        let index = Int(position)
        guard index < frames.count - 1 else { return frames[frames.count - 1] }
        let fraction = position - Double(index)
        let a = frames[index]
        let b = frames[index + 1]
        return ViewportFrame(
            magnification: a.magnification + (b.magnification - a.magnification) * fraction,
            anchor: CGPoint(
                x: a.anchor.x + (b.anchor.x - a.anchor.x) * fraction,
                y: a.anchor.y + (b.anchor.y - a.anchor.y) * fraction
            )
        )
    }

    /// Fraction of the pointer-follow dead zone relative to the visible
    /// crop: the pointer roams the middle before the camera moves.
    private static let deadZoneFraction: CGFloat = 0.28
    /// Low-pass time constant for camera moves, in seconds.
    private static let smoothingTau: Double = 0.45
    /// How quickly the crop hands over to a zoom cue's anchor as the
    /// zoom magnification ramps in.
    private static let zoomHandoffSpan: Double = 0.2

    /// Builds the reframe camera along the editor timeline.
    ///
    /// - Parameters:
    ///   - focus: Normalized (0...1) point of interest at an editor time -
    ///     the smoothed pointer when available; nil falls back to the zoom
    ///     anchor (which is the canvas center when unzoomed).
    static func build(
        preset: ExportAspectPreset,
        customAspectWidth: Int = 1920,
        customAspectHeight: Int = 1080,
        sourceSize: CGSize,
        viewportTimeline: ViewportTimeline,
        duration: TimeInterval,
        focus: (TimeInterval) -> CGPoint?
    ) -> ReframeTrack? {
        guard let targetRatio = preset.resolvedRatio(customWidth: customAspectWidth, customHeight: customAspectHeight),
              sourceSize.width > 0, sourceSize.height > 0,
              duration.isFinite, duration > 0 else {
            return nil
        }
        let sourceAspect = sourceSize.width / sourceSize.height

        // All geometry in normalized card units: the card is the target
        // aspect box, the content aspect-fills it, and a viewport frame's
        // anchor is the content point pinned at the card center.
        let card = CGSize(width: targetRatio, height: 1)
        let fillScale = max(card.width / sourceAspect, card.height / 1)
        let fill = CGSize(width: sourceAspect * fillScale, height: fillScale)

        let stepCount = max(2, Int((duration * Self.stepRate).rounded()) + 1)
        let dt = 1.0 / Self.stepRate
        var frames: [ViewportFrame] = []
        frames.reserveCapacity(stepCount)

        let smoothing = 1 - exp(-dt / Self.smoothingTau)
        var center = CGPoint(x: 0.5, y: 0.5)
        if let initial = focus(0) {
            center = initial
        }

        for step in 0..<stepCount {
            let time = Double(step) * dt
            let viewport = viewportTimeline.frame(at: time)
            let magnification = max(1, viewport.magnification)

            // Visible fraction of the content along each axis at this
            // magnification; also gives the coverage clamp for the anchor.
            let visibleX = min(1, card.width / (fill.width * magnification))
            let visibleY = min(1, card.height / (fill.height * magnification))

            let focusPoint = focus(time) ?? viewport.anchor

            // Dead-zone follow: only move enough to keep the focus inside
            // the central window of the visible crop, then low-pass it.
            var target = center
            let windowX = visibleX * Self.deadZoneFraction
            let windowY = visibleY * Self.deadZoneFraction
            if focusPoint.x > center.x + windowX { target.x = focusPoint.x - windowX }
            if focusPoint.x < center.x - windowX { target.x = focusPoint.x + windowX }
            if focusPoint.y > center.y + windowY { target.y = focusPoint.y - windowY }
            if focusPoint.y < center.y - windowY { target.y = focusPoint.y + windowY }
            center.x += (target.x - center.x) * smoothing
            center.y += (target.y - center.y) * smoothing

            // A zoom cue brings its own smoothed camera; hand the crop to
            // it as the magnification ramps so the two never disagree.
            let handoff = min(max((magnification - 1) / Self.zoomHandoffSpan, 0), 1)
            var anchor = CGPoint(
                x: center.x + (viewport.anchor.x - center.x) * handoff,
                y: center.y + (viewport.anchor.y - center.y) * handoff
            )

            // Never show past the content edge.
            anchor.x = min(max(anchor.x, visibleX / 2), 1 - visibleX / 2)
            anchor.y = min(max(anchor.y, visibleY / 2), 1 - visibleY / 2)
            // Fully visible axes pin to center (e.g. height in a 9:16 crop
            // of a landscape source at magnification 1).
            if visibleX >= 1 { anchor.x = 0.5 }
            if visibleY >= 1 { anchor.y = 0.5 }

            // Keep the follow camera continuous through zoom handoffs.
            center = anchor

            frames.append(ViewportFrame(magnification: magnification, anchor: anchor))
        }

        return ReframeTrack(
            preset: preset,
            sourceAspect: sourceAspect,
            frames: frames,
            duration: duration
        )
    }

    private init(
        preset: ExportAspectPreset,
        sourceAspect: CGFloat,
        frames: [ViewportFrame],
        duration: TimeInterval
    ) {
        self.preset = preset
        self.sourceAspect = sourceAspect
        self.frames = frames
        self.duration = duration
    }
}
