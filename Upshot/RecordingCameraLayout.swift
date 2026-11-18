//
//  RecordingCameraLayout.swift
//  Upshot
//
//  Camera layouts: how the screen card and the camera share the canvas.
//  A project has a default layout and any number of layout cues on the
//  timeline. Each layout resolves to a frame (where the screen card and
//  the camera sit, their corners and opacities) and the timeline morphs
//  from one frame to the next at every cue boundary, so the camera can
//  fill the canvas for an intro and then shrink into its corner when the
//  screen takes over. Preview and export resolve the same frames.
//

import CoreGraphics
import Foundation

// MARK: - Layout

nonisolated struct RecordingCameraLayout: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// The screen alone; the camera is off.
        case screen
        /// The camera fills the frame; the screen is hidden.
        case camera
        /// The screen with the camera in one of its corners.
        case pictureInPicture
        /// The screen and a tall camera card side by side (stacked on a
        /// portrait canvas).
        case split
        /// The screen with the person cut out of the camera's background,
        /// standing on the canvas's bottom edge.
        case cutout
    }

    enum Corner: String, Codable, CaseIterable, Sendable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }

    enum Shape: String, Codable, CaseIterable, Sendable {
        case circle
        case square
        case squircle
        case rectangle
        /// 3:4, taller than wide.
        case portrait
    }

    enum PositionPreset: String, Codable, CaseIterable, Sendable {
        case topLeading, topCenter, topTrailing
        case centerLeading, center, centerTrailing
        case bottomLeading, bottomCenter, bottomTrailing
        case custom

        var point: CGPoint {
            switch self {
            case .topLeading: CGPoint(x: 0, y: 0)
            case .topCenter: CGPoint(x: 0.5, y: 0)
            case .topTrailing: CGPoint(x: 1, y: 0)
            case .centerLeading: CGPoint(x: 0, y: 0.5)
            case .center: CGPoint(x: 0.5, y: 0.5)
            case .centerTrailing: CGPoint(x: 1, y: 0.5)
            case .bottomLeading: CGPoint(x: 0, y: 1)
            case .bottomCenter: CGPoint(x: 0.5, y: 1)
            case .bottomTrailing, .custom: CGPoint(x: 1, y: 1)
            }
        }

        init(_ corner: Corner) {
            switch corner {
            case .topLeading: self = .topLeading
            case .topTrailing: self = .topTrailing
            case .bottomLeading: self = .bottomLeading
            case .bottomTrailing: self = .bottomTrailing
            }
        }
    }

    enum Side: String, Codable, CaseIterable, Sendable {
        /// Left on a landscape canvas, top on a portrait one.
        case leading
        case trailing
    }

    /// Where a cutout stands along the bottom edge.
    enum Placement: String, Codable, CaseIterable, Sendable {
        case leading
        case center
        case trailing
    }

    /// How the screen takes the space a split gives it.
    enum ScreenFit: String, Codable, CaseIterable, Sendable {
        /// The whole recording, letterboxed by the camera card's height.
        case fit
        /// Both cards fill the frame's height; the recording is cropped.
        case fill
    }

    static let sizeRange: ClosedRange<Double> = 0.12...0.45
    static let dimensionRange: ClosedRange<Double> = 0.10...1
    static let splitRatioRange: ClosedRange<Double> = 0.45...1.2
    static let spacingRange: ClosedRange<Double> = 0...0.12
    static let cutoutSizeRange: ClosedRange<Double> = 0.3...0.9

    var kind: Kind
    var corner: Corner
    var shape: Shape
    /// Picture-in-picture camera width as a fraction of the canvas's
    /// smaller dimension.
    var size: Double
    var side: Side
    /// Split camera width over its height (landscape), or height over width
    /// (portrait canvas).
    var splitRatio: Double
    var screenFit: ScreenFit
    /// Split: one gap, as a fraction of the canvas's smaller dimension,
    /// around the frame and between the two cards.
    var spacing: Double
    var placement: Placement
    /// Cutout camera frame height as a fraction of the canvas's smaller
    /// dimension.
    var cutoutSize: Double
    var positionPreset: PositionPreset?
    var positionX: Double = 1
    var positionY: Double = 1
    var width: Double?
    var height: Double?

    var resolvedPositionPreset: PositionPreset { positionPreset ?? PositionPreset(corner) }

    var position: CGPoint {
        guard resolvedPositionPreset == .custom else { return resolvedPositionPreset.point }
        return CGPoint(
            x: Self.clamped(positionX, to: 0...1, fallback: 1),
            y: Self.clamped(positionY, to: 0...1, fallback: 1)
        )
    }

    var widthFraction: Double { Self.clamped(width ?? size, to: Self.dimensionRange, fallback: 0.26) }
    var heightFraction: Double {
        if shape == .circle { return widthFraction }
        return Self.clamped(height ?? (shape == .portrait ? widthFraction * 4 / 3 : widthFraction),
                            to: Self.dimensionRange, fallback: 0.26)
    }

    mutating func setPosition(_ point: CGPoint) {
        positionX = Self.clamped(Double(point.x), to: 0...1, fallback: 1)
        positionY = Self.clamped(Double(point.y), to: 0...1, fallback: 1)
        positionPreset = .custom
    }

    mutating func selectPosition(_ preset: PositionPreset) {
        positionPreset = preset
        guard preset != .custom else { return }
        positionX = Double(preset.point.x)
        positionY = Double(preset.point.y)
        switch preset {
        case .topLeading: corner = .topLeading
        case .topTrailing: corner = .topTrailing
        case .bottomLeading: corner = .bottomLeading
        case .bottomTrailing: corner = .bottomTrailing
        default: break
        }
    }

    mutating func selectShape(_ shape: Shape) {
        let current = widthFraction
        self.shape = shape
        if shape == .portrait {
            size = Self.clamped(current, to: Self.sizeRange, fallback: 0.26)
            width = nil
            height = nil
            return
        }
        width = min(current * (shape == .rectangle ? 16 / 9 : 1), 1)
        height = current
        size = width ?? current
    }

    init(
        kind: Kind = .pictureInPicture,
        corner: Corner = .bottomTrailing,
        shape: Shape = .square,
        size: Double = 0.26,
        side: Side = .trailing,
        splitRatio: Double = 0.75,
        screenFit: ScreenFit = .fill,
        spacing: Double = 0.04,
        placement: Placement = .trailing,
        cutoutSize: Double = 0.6
    ) {
        self.kind = kind
        self.corner = corner
        self.shape = shape
        self.size = Self.clamped(size, to: Self.sizeRange, fallback: 0.26)
        self.side = side
        self.splitRatio = Self.clamped(splitRatio, to: Self.splitRatioRange, fallback: 0.75)
        self.screenFit = screenFit
        self.spacing = Self.clamped(spacing, to: Self.spacingRange, fallback: 0.04)
        self.placement = placement
        self.cutoutSize = Self.clamped(cutoutSize, to: Self.cutoutSizeRange, fallback: 0.6)
    }

    static let screenOnly = RecordingCameraLayout(kind: .screen)
    static let cameraOnly = RecordingCameraLayout(kind: .camera)

    var showsCamera: Bool { kind != .screen }
    var showsScreen: Bool { kind != .camera }

    /// The arrangement only: two layouts with the same preset differ only in
    /// options the preset doesn't fix (corner, size, a split's side, and
    /// whether a bubble is square or portrait).
    func matches(preset: RecordingCameraLayout) -> Bool {
        guard kind == preset.kind else { return false }
        return kind != .pictureInPicture || (shape == .circle) == (preset.shape == .circle)
    }

    /// Applies a preset picked from the grid while keeping the options the
    /// user already tuned (corner, size, split side and width, a bubble's
    /// shape).
    func adopting(_ preset: RecordingCameraLayout) -> RecordingCameraLayout {
        var next = self
        next.kind = preset.kind
        if preset.kind == .pictureInPicture, !matches(preset: preset) {
            next.shape = preset.shape
        }
        return next
    }

    private enum CodingKeys: String, CodingKey {
        case kind, corner, shape, size, side, splitRatio, screenFit, spacing, placement, cutoutSize
        case positionPreset, positionX, positionY, width, height
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown values from a newer build fall back instead of failing
        // the whole project.
        func value<Value: RawRepresentable>(_ key: CodingKeys) -> Value? where Value.RawValue == String {
            guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
            return Value(rawValue: raw)
        }
        let kind: Kind? = value(.kind)
        let corner: Corner? = value(.corner)
        let shape: Shape? = value(.shape)
        let side: Side? = value(.side)
        let screenFit: ScreenFit? = value(.screenFit)
        let placement: Placement? = value(.placement)
        self.init(
            kind: kind ?? .pictureInPicture,
            corner: corner ?? .bottomTrailing,
            shape: shape ?? .square,
            size: try container.decodeIfPresent(Double.self, forKey: .size) ?? 0.26,
            side: side ?? .trailing,
            splitRatio: try container.decodeIfPresent(Double.self, forKey: .splitRatio) ?? 0.75,
            screenFit: screenFit ?? .fill,
            spacing: try container.decodeIfPresent(Double.self, forKey: .spacing) ?? 0.04,
            placement: placement ?? .trailing,
            cutoutSize: try container.decodeIfPresent(Double.self, forKey: .cutoutSize) ?? 0.6
        )
        positionPreset = value(.positionPreset)
        positionX = Self.clamped(try container.decodeIfPresent(Double.self, forKey: .positionX) ?? Double(position.x), to: 0...1, fallback: 1)
        positionY = Self.clamped(try container.decodeIfPresent(Double.self, forKey: .positionY) ?? Double(position.y), to: 0...1, fallback: 1)
        width = try container.decodeIfPresent(Double.self, forKey: .width).map {
            Self.clamped($0, to: Self.dimensionRange, fallback: 0.26)
        }
        height = try container.decodeIfPresent(Double.self, forKey: .height).map {
            Self.clamped($0, to: Self.dimensionRange, fallback: 0.26)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(corner.rawValue, forKey: .corner)
        try container.encode(shape.rawValue, forKey: .shape)
        try container.encode(size, forKey: .size)
        try container.encode(side.rawValue, forKey: .side)
        try container.encode(splitRatio, forKey: .splitRatio)
        try container.encode(screenFit.rawValue, forKey: .screenFit)
        try container.encode(spacing, forKey: .spacing)
        try container.encode(placement.rawValue, forKey: .placement)
        try container.encode(cutoutSize, forKey: .cutoutSize)
        try container.encodeIfPresent(positionPreset, forKey: .positionPreset)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

nonisolated extension RecordingCameraLayout {
    /// The layout grid, in reading order. A portrait camera is a bubble's
    /// shape rather than a layout of its own.
    static let presets: [RecordingCameraLayout] = [
        .screenOnly,
        .cameraOnly,
        RecordingCameraLayout(kind: .pictureInPicture, shape: .square),
        RecordingCameraLayout(kind: .pictureInPicture, shape: .circle),
        RecordingCameraLayout(kind: .split),
        RecordingCameraLayout(kind: .cutout)
    ]

    var title: String {
        switch kind {
        case .screen: "Screen"
        case .camera: "Camera"
        case .pictureInPicture:
            switch shape {
            case .circle: "Circle"
            case .square, .squircle: "Bubble"
            case .rectangle: "Rectangle"
            case .portrait: "Portrait"
            }
        case .split: "Split"
        case .cutout: "Cutout"
        }
    }

    /// Spelled out for help tags and menus.
    var detailedTitle: String {
        switch kind {
        case .screen: "Screen only"
        case .camera: "Camera full frame"
        case .pictureInPicture: "Screen with \(title.lowercased()) camera"
        case .split: "Screen and camera side by side"
        case .cutout: "Screen with you cut out of the camera"
        }
    }

    var systemImage: String {
        switch kind {
        case .screen: "rectangle"
        case .camera: "person.crop.rectangle"
        case .pictureInPicture: shape == .circle ? "pip" : "rectangle.inset.bottomright.filled"
        case .split: "rectangle.split.2x1"
        case .cutout: "person.and.background.dotted"
        }
    }

    /// Migrates the free-form bubble of projects saved before layouts: the
    /// nearest corner, its size, and a circle when it was fully rounded.
    static func migrated(center: CGPoint, size: Double, roundness: Double) -> RecordingCameraLayout {
        let corner: Corner = switch (center.x < 0.5, center.y < 0.5) {
        case (true, true): .topLeading
        case (false, true): .topTrailing
        case (true, false): .bottomLeading
        case (false, false): .bottomTrailing
        }
        return RecordingCameraLayout(
            kind: .pictureInPicture,
            corner: corner,
            shape: roundness >= 0.49 ? .circle : .square,
            size: size
        )
    }

    /// Normalized canvas center the bubble roughly occupies, written beside
    /// the layout so older builds still open the project sensibly.
    var legacyCenter: CGPoint {
        if positionPreset != nil { return CGPoint(x: 0.15 + position.x * 0.7, y: 0.15 + position.y * 0.7) }
        let near = 0.15, far = 0.85
        return switch corner {
        case .topLeading: CGPoint(x: near, y: near)
        case .topTrailing: CGPoint(x: far, y: near)
        case .bottomLeading: CGPoint(x: near, y: far)
        case .bottomTrailing: CGPoint(x: far, y: far)
        }
    }

    /// The layout a new cue starts with, given the layout it interrupts:
    /// usually "the other one" - the camera when the screen has the floor.
    static func suggestedCue(over base: RecordingCameraLayout) -> RecordingCameraLayout {
        switch base.kind {
        case .camera: base.adopting(RecordingCameraLayout(kind: .pictureInPicture))
        case .screen, .pictureInPicture, .split, .cutout: base.adopting(.cameraOnly)
        }
    }
}

// MARK: - Cues

/// A stretch of the recording shown in a layout other than the default.
/// Times are source seconds, like zoom cues, so cuts and speed changes
/// carry the cue with the footage it was placed on.
nonisolated struct RecordingCameraLayoutCue: Identifiable, Codable, Equatable, Sendable {
    static let minimumDuration: TimeInterval = 0.5

    var id: UUID
    var start: TimeInterval
    var end: TimeInterval
    var layout: RecordingCameraLayout

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, layout: RecordingCameraLayout) {
        self.id = id
        self.start = start
        self.end = end
        self.layout = layout
    }

    var duration: TimeInterval { max(0, end - start) }
}

/// One cue as the timeline draws it, in editor time.
nonisolated struct RecordingCameraLayoutTimelineBlock: Identifiable, Equatable, Sendable {
    let cue: RecordingCameraLayoutCue
    let editorStart: TimeInterval
    let editorEnd: TimeInterval

    var fragmentID: UUID? = nil

    var id: UUID { fragmentID ?? cue.id }
}

// MARK: - Frames

/// Where everything sits at one moment, in top-left canvas points.
nonisolated struct RecordingCameraLayoutFrame: Equatable, Sendable {
    /// The resting card's aspect, except in a fill split, where the
    /// content covers it and is cropped.
    var screenRect: CGRect
    var screenOpacity: CGFloat
    var cameraRect: CGRect
    var cameraCornerRadius: CGFloat
    var cameraOpacity: CGFloat
    /// 0 shows the whole camera picture in its frame; 1 shows only the
    /// person, cut out of the background. A morph blends the two, so the
    /// background melts away as the camera settles into a cutout.
    var cameraCutout: CGFloat = 0
    var cameraSquircle: CGFloat = 0
    var cameraBubble: CGFloat = 0

    /// Blends two frames. Something hidden at one end appears from (or
    /// leaves into) a slightly smaller copy of where it sits at the other,
    /// so it settles in place instead of flying in from nowhere.
    static func interpolate(
        _ from: RecordingCameraLayoutFrame,
        _ to: RecordingCameraLayoutFrame,
        progress: CGFloat
    ) -> RecordingCameraLayoutFrame {
        let t = min(max(progress, 0), 1)
        var from = from
        var to = to
        if from.screenOpacity <= 0.001 { from.screenRect = to.screenRect.scaledAboutCenter(0.94) }
        if to.screenOpacity <= 0.001 { to.screenRect = from.screenRect.scaledAboutCenter(0.94) }
        if from.cameraOpacity <= 0.001 {
            from.cameraRect = to.cameraRect.scaledAboutCenter(0.82)
            from.cameraCornerRadius = to.cameraCornerRadius * 0.82
            from.cameraCutout = to.cameraCutout
            from.cameraSquircle = to.cameraSquircle
        }
        if to.cameraOpacity <= 0.001 {
            to.cameraRect = from.cameraRect.scaledAboutCenter(0.82)
            to.cameraCornerRadius = from.cameraCornerRadius * 0.82
            to.cameraCutout = from.cameraCutout
            to.cameraSquircle = from.cameraSquircle
        }
        // Fades run in the first part of the move, so a layer arriving is
        // solid well before it lands and one leaving is gone before it stops.
        let fade = min(t / 0.6, 1)
        return RecordingCameraLayoutFrame(
            screenRect: from.screenRect.lerp(to: to.screenRect, t),
            screenOpacity: from.screenOpacity.lerp(to: to.screenOpacity, fade),
            cameraRect: from.cameraRect.lerp(to: to.cameraRect, t),
            cameraCornerRadius: from.cameraCornerRadius.lerp(to: to.cameraCornerRadius, t),
            cameraOpacity: from.cameraOpacity.lerp(to: to.cameraOpacity, fade),
            cameraCutout: from.cameraCutout.lerp(to: to.cameraCutout, t),
            cameraSquircle: from.cameraSquircle.lerp(to: to.cameraSquircle, t),
            cameraBubble: from.cameraBubble.lerp(to: to.cameraBubble, t)
        )
    }
}

/// Resolves layouts against one canvas. Built from the resting layout (the
/// card the style and video crop produce), which every layout scales and
/// moves rather than reshapes.
nonisolated struct RecordingCameraLayoutResolver: Sendable {
    /// Webcams almost always deliver 16:9; the real camera's aspect is
    /// passed in wherever it's known.
    static let defaultCameraAspect: CGFloat = 16 / 9

    let base: RecordingStudioLayout
    let showsCamera: Bool
    /// The camera picture's width over its height. A cutout's frame takes
    /// it exactly, so the whole picture shows and nothing is cropped.
    let cameraAspect: CGFloat
    private let contentArea: CGRect
    private let minDimension: CGFloat
    private let roundness: CGFloat
    private let margin: CGFloat
    /// The corner camera's scale once a zoom lands; 1 when it doesn't shrink.
    let zoomedCameraScale: CGFloat
    private let zoomResponse: RecordingCameraZoomResponse
    private let reactsToZoom: Bool
    private let pictureCrop: CGRect

    init(
        base: RecordingStudioLayout,
        style: RecordingStudioStyle,
        showsCamera: Bool,
        cameraAspect: CGFloat = Self.defaultCameraAspect
    ) {
        self.base = base
        self.showsCamera = showsCamera
        self.cameraAspect = cameraAspect.isFinite && cameraAspect > 0
            ? min(max(cameraAspect, 0.3), 3.5)
            : Self.defaultCameraAspect
        let canvas = base.canvasSize
        minDimension = max(1, min(canvas.width, canvas.height))
        let inset = min(max(style.padding, 0), 0.475) * minDimension
        contentArea = style.paddingSides == nil
            ? CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
            : base.cardRect
        roundness = min(max(style.camera.roundness, 0), 0.5)
        margin = RecordingStudioLayout.bubbleMargin(forMinDimension: minDimension)
        zoomedCameraScale = style.camera.shrinksDuringZoom ? 1 - style.camera.zoomShrinkAmount : 1
        zoomResponse = style.camera.zoomResponse
        reactsToZoom = style.camera.shrinksDuringZoom
        pictureCrop = style.camera.pictureCrop
    }

    /// A corner camera's scale for how far the screen has zoomed: full
    /// size unzoomed, `zoomedCameraScale` once the zoom lands, and in
    /// between on the zoom's own spring, so the two arrive together. The
    /// talking head has the floor until something happens on screen.
    func cameraScale(forZoomProgress progress: Double) -> CGFloat {
        let t = CGFloat(min(max(progress, 0), 1))
        return 1 - (1 - zoomedCameraScale) * t
    }

    func cameraScale(forMagnification magnification: Double, zoomProgress: Double) -> CGFloat {
        guard zoomResponse == .magnification else { return cameraScale(forZoomProgress: zoomProgress) }
        guard reactsToZoom else { return 1 }
        let zoom = magnification.isFinite ? max(1, magnification) : 1
        return 1 - (1 - zoomedCameraScale) * CGFloat(1 - 1 / zoom)
    }

    func position(for rect: CGRect) -> CGPoint {
        let card = base.cardRect
        return CGPoint(
            x: min(max((rect.minX - card.minX - margin) / max(0.001, card.width - margin * 2 - rect.width), 0), 1),
            y: min(max((rect.minY - card.minY - margin) / max(0.001, card.height - margin * 2 - rect.height), 0), 1)
        )
    }

    /// `zoomProgress` is how far the screen has zoomed at that moment
    /// (ViewportTimeline.zoomProgress), which a corner camera shrinks with.
    func frame(for layout: RecordingCameraLayout, zoomProgress: Double = 0, magnification: Double = 1) -> RecordingCameraLayoutFrame {
        let card = base.cardRect
        let layout = showsCamera ? layout : .screenOnly
        switch layout.kind {
        case .screen:
            var hidden = RecordingCameraLayout(kind: .pictureInPicture)
            hidden.corner = layout.corner
            let ghost = pipCamera(for: hidden, in: card)
            return RecordingCameraLayoutFrame(
                screenRect: card,
                screenOpacity: 1,
                cameraRect: ghost.rect,
                cameraCornerRadius: ghost.radius,
                cameraOpacity: 0
            )
        case .camera:
            return RecordingCameraLayoutFrame(
                screenRect: card,
                screenOpacity: 0,
                cameraRect: contentArea,
                cameraCornerRadius: base.cardCornerRadius,
                cameraOpacity: 1
            )
        case .pictureInPicture:
            let camera = pipCamera(for: layout, in: card, scale: cameraScale(forMagnification: magnification, zoomProgress: zoomProgress))
            return RecordingCameraLayoutFrame(
                screenRect: card,
                screenOpacity: 1,
                cameraRect: camera.rect,
                cameraCornerRadius: camera.radius,
                cameraOpacity: 1,
                cameraSquircle: layout.shape == .squircle ? 1 : 0,
                cameraBubble: 1
            )
        case .split:
            let split = splitRects(for: layout)
            let resting = RecordingCameraLayoutFrame(
                screenRect: split.screen,
                screenOpacity: 1,
                cameraRect: split.camera,
                cameraCornerRadius: base.cardCornerRadius,
                cameraOpacity: 1
            )
            guard zoomProgress > 0 else { return resting }
            let aspect = min(max(split.camera.width / max(split.camera.height, 1), 9 / 16), 16 / 9)
            let side = minDimension * 0.5
            let cameraSize = CGSize(width: min(side, side * aspect), height: min(side, side / aspect))
            let inset = max(minDimension * 0.01, CGFloat(layout.spacing) * minDimension * 0.25)
            let isLandscape = base.canvasSize.width >= base.canvasSize.height
            let leading = layout.side == .leading
            let camera = CGRect(
                x: isLandscape && leading ? inset : base.canvasSize.width - inset - cameraSize.width,
                y: !isLandscape && leading ? inset : base.canvasSize.height - inset - cameraSize.height,
                width: cameraSize.width,
                height: cameraSize.height
            )
            let zoomed = RecordingCameraLayoutFrame(
                screenRect: card.insetBy(
                    dx: -max(0, split.screen.width - card.width) / 2,
                    dy: -max(0, split.screen.height - card.height) / 2
                ),
                screenOpacity: 1,
                cameraRect: camera,
                cameraCornerRadius: base.cardCornerRadius,
                cameraOpacity: 1
            )
            return .interpolate(resting, zoomed, progress: CGFloat(zoomProgress))
        case .cutout:
            return RecordingCameraLayoutFrame(
                screenRect: card,
                screenOpacity: 1,
                cameraRect: cutoutCamera(for: layout, scale: zoomResponse == .progress
                    ? cameraScale(forZoomProgress: zoomProgress)
                    : (reactsToZoom ? 1 - 0.1 * CGFloat(min(max(zoomProgress, 0), 1)) : 1)),
                cameraCornerRadius: 0,
                cameraOpacity: 1,
                cameraCutout: 1
            )
        }
    }

    func frame(
        for state: RecordingCameraLayoutTimeline.State,
        zoomProgress: Double = 0,
        magnification: Double = 1
    ) -> RecordingCameraLayoutFrame {
        switch state {
        case .settled(let layout):
            return frame(for: layout, zoomProgress: zoomProgress, magnification: magnification)
        case .transition(let from, let to, let progress):
            return .interpolate(
                frame(for: from, zoomProgress: zoomProgress, magnification: magnification),
                frame(for: to, zoomProgress: zoomProgress, magnification: magnification),
                progress: CGFloat(RecordingCameraLayoutTimeline.ease(progress))
            )
        }
    }

    /// The resting layout moved into a frame.
    func layout(
        for state: RecordingCameraLayoutTimeline.State,
        zoomProgress: Double = 0,
        magnification: Double = 1
    ) -> RecordingStudioLayout {
        base.applying(frame(for: state, zoomProgress: zoomProgress, magnification: magnification))
    }

    /// The camera tucked into a corner of the screen card.
    private func pipCamera(
        for layout: RecordingCameraLayout,
        in card: CGRect,
        scale: CGFloat = 1
    ) -> (rect: CGRect, radius: CGFloat) {
        if layout.width != nil || layout.height != nil || layout.shape == .rectangle || layout.shape == .squircle {
            let width = CGFloat(layout.widthFraction) * minDimension * scale
            let heightFraction = layout.shape == .rectangle
                ? RecordingCameraCropGeometry.matchedHeight(width: layout.widthFraction, height: layout.heightFraction,
                                                            sourceAspect: cameraAspect, crop: pictureCrop)
                : layout.heightFraction
            let height = CGFloat(heightFraction) * minDimension * scale
            let maxWidth = max(0, card.width - margin * 2) * 0.62
            let maxHeight = max(0, card.height - margin * 2) * 0.62
            let reduction = min(1, maxWidth / max(width, 0.001), maxHeight / max(height, 0.001))
            let size = CGSize(width: width * reduction, height: height * reduction)
            let point = layout.position
            let rect = CGRect(
                x: card.minX + margin + max(0, card.width - margin * 2 - size.width) * point.x,
                y: card.minY + margin + max(0, card.height - margin * 2 - size.height) * point.y,
                width: size.width, height: size.height
            )
            let short = min(size.width, size.height)
            return (rect, layout.shape == .circle ? short / 2 : max(4, roundness * short))
        }
        let requested = CGFloat(layout.size) * minDimension
        let aspect: CGFloat = layout.shape == .portrait ? 3 / 4 : 1
        // Never let the camera outgrow the card it sits in.
        let maxWidth = max(24, min(card.width - margin * 2, (card.height - margin * 2) * aspect) * 0.62)
        // Shrinks toward its corner: the margins stay put.
        let width = max(24, min(requested, maxWidth)) * scale
        let size = CGSize(width: width, height: width / aspect)
        let point = layout.position
        let x = card.minX + margin + (card.width - margin * 2 - size.width) * point.x
        let y = card.minY + margin + (card.height - margin * 2 - size.height) * point.y
        let short = min(size.width, size.height)
        let radius = layout.shape == .circle ? short / 2 : max(4, roundness * short)
        return (CGRect(origin: CGPoint(x: x, y: y), size: size), radius)
    }

    /// The whole camera picture, standing on the canvas's bottom edge so the
    /// edge crops the body where the picture ends. To the side, the frame
    /// sits flush with the canvas edge when it fits, which puts the person
    /// - usually mid-picture - well in from the edge; a frame wider than
    /// that half of the canvas centers instead. It shrinks for a zoom
    /// toward the edges it rests on.
    private func cutoutCamera(for layout: RecordingCameraLayout, scale: CGFloat = 1) -> CGRect {
        let canvas = base.canvasSize
        let height = max(24, CGFloat(layout.cutoutSize) * minDimension) * scale
        let width = height * cameraAspect
        let midX: CGFloat = switch layout.placement {
        case .leading: min(width / 2, canvas.width / 2)
        case .center: canvas.width / 2
        case .trailing: max(canvas.width - width / 2, canvas.width / 2)
        }
        return CGRect(x: midX - width / 2, y: canvas.height - height, width: width, height: height)
    }

    /// The screen card and a camera card side by side (stacked on a
    /// portrait canvas), with one spacing around the pair and between
    /// them. Fill gives both cards the frame's full height and lets the
    /// screen take the rest of the width, cropping the recording; Fit keeps
    /// the whole recording and matches the camera's height to it.
    private func splitRects(for layout: RecordingCameraLayout) -> (screen: CGRect, camera: CGRect) {
        let canvas = CGRect(origin: .zero, size: base.canvasSize)
        let gap = CGFloat(layout.spacing) * minDimension
        let area = canvas.insetBy(dx: min(gap, canvas.width / 4), dy: min(gap, canvas.height / 4))
        // Fit is measured against the selected source, even when the output
        // aspect has already cropped the resting screen card.
        let visibleSize = CGSize(
            width: base.contentFillSize.width * base.contentCropRect.width,
            height: base.contentFillSize.height * base.contentCropRect.height
        )
        let aspect = visibleSize.height > 0 ? max(0.1, visibleSize.width / visibleSize.height) : 16 / 9
        let ratio = CGFloat(layout.splitRatio)
        let cameraFirst = layout.side == .leading
        let fills = layout.screenFit == .fill

        if area.width >= area.height {
            let screenSize: CGSize
            let cameraSize: CGSize
            if fills {
                let height = area.height
                let cameraWidth = min(height * ratio, area.width * 0.6)
                cameraSize = CGSize(width: cameraWidth, height: height)
                screenSize = CGSize(width: max(1, area.width - gap - cameraWidth), height: height)
            } else {
                let height = max(1, min(area.height, (area.width - gap) / (aspect + ratio)))
                screenSize = CGSize(width: height * aspect, height: height)
                cameraSize = CGSize(width: height * ratio, height: height)
            }
            let total = screenSize.width + gap + cameraSize.width
            let x = area.midX - total / 2
            let y = area.midY - screenSize.height / 2
            let screenX = cameraFirst ? x + cameraSize.width + gap : x
            let cameraX = cameraFirst ? x : x + screenSize.width + gap
            return (
                CGRect(origin: CGPoint(x: screenX, y: y), size: screenSize),
                CGRect(origin: CGPoint(x: cameraX, y: y), size: cameraSize)
            )
        }

        let screenSize: CGSize
        let cameraSize: CGSize
        if fills {
            let width = area.width
            let cameraHeight = min(width * ratio, area.height * 0.6)
            cameraSize = CGSize(width: width, height: cameraHeight)
            screenSize = CGSize(width: width, height: max(1, area.height - gap - cameraHeight))
        } else {
            let width = max(1, min(area.width, (area.height - gap) / (1 / aspect + ratio)))
            screenSize = CGSize(width: width, height: width / aspect)
            cameraSize = CGSize(width: width, height: width * ratio)
        }
        let total = screenSize.height + gap + cameraSize.height
        let x = area.midX - screenSize.width / 2
        let y = area.midY - total / 2
        let screenY = cameraFirst ? y + cameraSize.height + gap : y
        let cameraY = cameraFirst ? y : y + screenSize.height + gap
        return (
            CGRect(origin: CGPoint(x: x, y: screenY), size: screenSize),
            CGRect(origin: CGPoint(x: x, y: cameraY), size: cameraSize)
        )
    }
}

extension RecordingStudioLayout {
    /// This layout with its card and camera moved into `frame`. The content
    /// scales uniformly to cover the new card - exactly when the card keeps
    /// its shape, cropping the overflow when a fill split reshapes it - so
    /// zoom and cursor math carry over unchanged.
    nonisolated func applying(_ frame: RecordingCameraLayoutFrame) -> RecordingStudioLayout {
        let visibleWidth = contentFillSize.width * contentCropRect.width
        let visibleHeight = contentFillSize.height * contentCropRect.height
        let scale = visibleWidth > 0 && visibleHeight > 0
            ? max(frame.screenRect.width / visibleWidth, frame.screenRect.height / visibleHeight)
            : 1
        return RecordingStudioLayout(
            canvasSize: canvasSize,
            cardRect: frame.screenRect,
            cardCornerRadius: cardCornerRadius,
            bubbleRect: frame.cameraRect,
            bubbleCornerRadius: frame.cameraCornerRadius,
            contentFillSize: CGSize(
                width: contentFillSize.width * scale,
                height: contentFillSize.height * scale
            ),
            contentCropRect: contentCropRect,
            screenOpacity: frame.screenOpacity,
            cameraOpacity: frame.cameraOpacity,
            cameraCutout: Self.melt(frame.cameraCutout),
            cameraSquircle: frame.cameraSquircle,
            cameraBubble: frame.cameraBubble
        )
    }

    /// The background melts through the middle of a morph, so a framed
    /// camera leaves framed and lands as just the person, and a cutout
    /// leaves as the person and lands framed: the change is over before
    /// the camera settles, either way.
    nonisolated private static func melt(_ progress: CGFloat) -> CGFloat {
        let t = min(max((progress - 0.2) / 0.6, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Timeline

/// The default layout and every cue, resolved into change points on the
/// edited (editor-time) timeline. Each change morphs over a fixed length,
/// shortened when the next change comes sooner, so a morph always lands
/// before the next one begins.
nonisolated struct RecordingCameraLayoutTimeline: Equatable, Sendable {
    static let transitionDuration: TimeInterval = 0.6

    struct Change: Equatable, Sendable {
        let time: TimeInterval
        let from: RecordingCameraLayout
        let to: RecordingCameraLayout
        let duration: TimeInterval
    }

    enum State: Equatable, Sendable {
        case settled(RecordingCameraLayout)
        case transition(from: RecordingCameraLayout, to: RecordingCameraLayout, progress: Double)

        var settledLayout: RecordingCameraLayout? {
            if case .settled(let layout) = self { return layout }
            return nil
        }
    }

    let initial: RecordingCameraLayout
    let changes: [Change]

    static func constant(_ layout: RecordingCameraLayout) -> RecordingCameraLayoutTimeline {
        RecordingCameraLayoutTimeline(initial: layout, changes: [])
    }

    /// Every layout the timeline ever shows.
    var layouts: [RecordingCameraLayout] {
        [initial] + changes.map(\.to)
    }

    var usesCamera: Bool {
        layouts.contains(where: \.showsCamera)
    }

    /// Whether any stretch needs the person segmented from the camera.
    var usesCutout: Bool {
        layouts.contains { $0.kind == .cutout }
    }

    static func blocks(
        for cues: [RecordingCameraLayoutCue],
        clipTimeline: RecordingClipTimeline
    ) -> [RecordingCameraLayoutTimelineBlock] {
        cues.flatMap { cue in
            clipTimeline.editorRegions(overlapping: cue.start, sourceEnd: cue.end)
                .enumerated().map { index, region in
                    RecordingCameraLayoutTimelineBlock(
                        cue: cue,
                        editorStart: region.start,
                        editorEnd: region.end,
                        fragmentID: index == 0 ? nil : region.fragmentID(for: cue.id)
                    )
                }
        }
        .sorted { $0.editorStart < $1.editorStart }
    }

    static func build(
        defaultLayout: RecordingCameraLayout,
        cues: [RecordingCameraLayoutCue],
        clipTimeline: RecordingClipTimeline
    ) -> RecordingCameraLayoutTimeline {
        build(defaultLayout: defaultLayout, blocks: blocks(for: cues, clipTimeline: clipTimeline))
    }

    static func build(
        defaultLayout: RecordingCameraLayout,
        blocks: [RecordingCameraLayoutTimelineBlock]
    ) -> RecordingCameraLayoutTimeline {
        var initial = defaultLayout
        var points: [(time: TimeInterval, layout: RecordingCameraLayout)] = []
        var cursor: TimeInterval = 0
        var hasBlock = false
        for block in blocks where block.editorEnd > block.editorStart {
            let start = max(block.editorStart, cursor)
            guard block.editorEnd > start else { continue }
            // A gap after a cue returns to the default until the next one.
            if hasBlock, start > cursor {
                points.append((cursor, defaultLayout))
            }
            if !hasBlock, start <= 0.0001 {
                initial = block.cue.layout
            } else {
                points.append((start, block.cue.layout))
            }
            hasBlock = true
            cursor = block.editorEnd
        }
        if hasBlock {
            points.append((cursor, defaultLayout))
        }

        var changes: [Change] = []
        var current = initial
        for (index, point) in points.enumerated() where point.layout != current {
            let next = points[(index + 1)...].first?.time ?? .infinity
            changes.append(Change(
                time: point.time,
                from: current,
                to: point.layout,
                duration: max(0, min(transitionDuration, next - point.time))
            ))
            current = point.layout
        }
        return RecordingCameraLayoutTimeline(initial: initial, changes: changes)
    }

    func state(at time: TimeInterval) -> State {
        // Last change at or before `time`.
        var low = 0
        var high = changes.count
        while low < high {
            let mid = (low + high) / 2
            if changes[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return .settled(initial) }
        let change = changes[low - 1]
        let elapsed = time - change.time
        guard change.duration > 0, elapsed < change.duration else { return .settled(change.to) }
        return .transition(from: change.from, to: change.to, progress: elapsed / change.duration)
    }

    /// The layout in effect at `time`, or the one being morphed into.
    func layout(at time: TimeInterval) -> RecordingCameraLayout {
        switch state(at: time) {
        case .settled(let layout): layout
        case .transition(_, let to, _): to
        }
    }

    /// A critically damped spring normalized to land exactly at 1: it
    /// leaves at rest, covers most of the way early, settles softly, and
    /// never overshoots.
    static func ease(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        let omega = 7.5
        let end = 1 - (1 + omega) * exp(-omega)
        return (1 - (1 + omega * t) * exp(-omega * t)) / end
    }
}

// MARK: - Geometry helpers

private extension CGFloat {
    nonisolated func lerp(to other: CGFloat, _ t: CGFloat) -> CGFloat {
        self + (other - self) * t
    }
}

private extension CGRect {
    nonisolated func lerp(to other: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: minX.lerp(to: other.minX, t),
            y: minY.lerp(to: other.minY, t),
            width: width.lerp(to: other.width, t),
            height: height.lerp(to: other.height, t)
        )
    }

    nonisolated func scaledAboutCenter(_ scale: CGFloat) -> CGRect {
        CGRect(
            x: midX - width * scale / 2,
            y: midY - height * scale / 2,
            width: width * scale,
            height: height * scale
        )
    }
}
