import AppKit
import SwiftUI

extension InspectorValueFormat {
    static let seconds = InspectorValueFormat(
        multiplier: 1,
        fractionDigits: 2,
        suffix: " s",
        showsPositiveSign: false,
        step: 0.01,
        acceptedSuffixes: ["seconds", "second", "sec", "s"]
    )
}

private enum StudioOverlaySwatches {
    static let text: [RecordingOverlayColor] = [
        .white,
        .black,
        RecordingOverlayColor(red: 1, green: 0.84, blue: 0.04),
        RecordingOverlayColor(red: 1, green: 0.27, blue: 0.23),
        RecordingOverlayColor(red: 0.04, green: 0.52, blue: 1),
        RecordingOverlayColor(red: 0.2, green: 0.78, blue: 0.35)
    ]

    static let background: [RecordingOverlayColor] = [
        .black,
        RecordingOverlayColor(red: 0, green: 0, blue: 0, alpha: 0.6),
        .white,
        RecordingOverlayColor(red: 1, green: 0.84, blue: 0.04),
        RecordingOverlayColor(red: 0.04, green: 0.52, blue: 1),
        RecordingOverlayColor(red: 0.69, green: 0.32, blue: 0.87)
    ]
}

private struct StudioOverlayColorRow: View {
    let presets: [RecordingOverlayColor]
    let selection: RecordingOverlayColor
    let onPick: (RecordingOverlayColor) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(presets, id: \.self) { color in
                InspectorTile(title: "Color", isSelected: color == selection) {
                    onPick(color)
                } content: {
                    swatch(color)
                }
            }
            InspectorTile(title: "Custom color", isSelected: !presets.contains(selection)) {
                AnnotationColorPanelBridge.shared.present(current: selection.nsColor) { color in
                    onPick(RecordingOverlayColor(color))
                }
            } content: {
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
            }
        }
    }

    private func swatch(_ color: RecordingOverlayColor) -> some View {
        Canvas { context, size in
            if color.alpha < 0.999 {
                let cell = size.width / 4
                for row in 0..<Int(ceil(size.height / cell)) {
                    for column in 0..<4 where (row + column).isMultiple(of: 2) {
                        context.fill(
                            Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                            with: .color(.primary.opacity(0.12))
                        )
                    }
                }
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(cgColor: color.cgColor)))
        }
    }
}

struct StudioTextInspectorControls: View {
    @Bindable var model: RecordingStudioModel
    let text: RecordingTextOverlay

    @State private var side: Side = .enter

    private enum Side: Hashable, CaseIterable {
        case enter
        case exit

        var title: String { self == .enter ? "In" : "Out" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            TextField("Type something…", text: binding(\.text, action: "Edit Text"), axis: .vertical)
                .lineLimit(1...6)
                .font(.dsBody)
                .padding(.vertical, Space.xs)
                .interfaceFieldChrome()

            StudioInspectorGroup("Font") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.xs) {
                    ForEach(RecordingTextFont.allCases) { font in
                        InspectorTile(title: font.title, aspectRatio: 2.4, isSelected: text.font == font) {
                            edit("Change Font") { $0.font = font }
                        } content: {
                            Rectangle()
                                .fill(Palette.fill)
                                .overlay {
                                    Text(font.title)
                                        .font(Font(font.font(size: 12, isBold: text.isBold)))
                                        .foregroundStyle(Palette.label)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .padding(.horizontal, Space.xs)
                                }
                        }
                    }
                }

                InspectorFieldPair {
                    InspectorSlider(
                        "Size",
                        value: Binding(
                            get: { CGFloat(text.fontSize) },
                            set: { value in edit("Change Text Size") { $0.fontSize = Double(value) } }
                        ),
                        range: CGFloat(RecordingTextOverlay.fontSizeRange.lowerBound)...CGFloat(RecordingTextOverlay.fontSizeRange.upperBound),
                        format: .percent(fractionDigits: 1)
                    )
                    .help("Font size as a share of the video's height")
                } trailing: {
                    InterfaceToggleRow("Bold", isOn: Binding(
                        get: { text.isBold },
                        set: { isBold in edit("Change Text Weight") { $0.isBold = isBold } }
                    ))
                }

                StudioOverlayColorRow(presets: StudioOverlaySwatches.text, selection: text.color) { color in
                    edit("Change Text Color") { $0.color = color }
                }
            }

            StudioInspectorGroup(
                "Background",
                isOn: Binding(
                    get: { text.hasBackground },
                    set: { hasBackground in edit("Change Text Background") { $0.hasBackground = hasBackground } }
                ),
                toggleTitle: "Show text background"
            ) {
                if text.hasBackground {
                    StudioOverlayColorRow(presets: StudioOverlaySwatches.background, selection: text.backgroundColor) { color in
                        edit("Change Text Background") { $0.backgroundColor = color }
                    }
                    .transition(.opacity)
                }
            }

            StudioInspectorGroup("Animation") {
                InterfaceModeSwitch(
                    "Animation phase",
                    selection: $side,
                    options: Side.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.title) }
                )

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3), spacing: Space.s) {
                    ForEach(RecordingTextAnimation.Effect.allCases) { effect in
                        StudioTextEffectTile(
                            text: text,
                            isExit: side == .exit,
                            effect: effect,
                            isSelected: animation.effect == effect
                        ) {
                            editAnimation("Change Text Animation") { $0.effect = effect }
                        }
                    }
                }

                StudioInspectorModeSwitchRow(
                    "Animate",
                    selection: Binding(
                        get: { animation.unit },
                        set: { unit in editAnimation("Change Text Animation") { $0.unit = unit } }
                    ),
                    options: RecordingTextAnimation.Unit.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.title) }
                )
                .help("Animate the whole text at once, word by word, or letter by letter")

                if animation.unit != .all {
                    StudioInspectorPickerRow("Order", selection: Binding(
                        get: { animation.order },
                        set: { order in editAnimation("Change Text Animation") { $0.order = order } }
                    )) {
                        ForEach(RecordingTextAnimation.Order.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .transition(.opacity)
                }

                InspectorFieldPair {
                    InspectorSlider(
                        "Duration",
                        value: animationBinding(\.duration),
                        range: CGFloat(RecordingTextAnimation.durationRange.lowerBound)...CGFloat(RecordingTextAnimation.durationRange.upperBound),
                        format: .seconds
                    )
                } trailing: {
                    InspectorSlider(
                        "Stagger",
                        value: animationBinding(\.delay),
                        range: CGFloat(RecordingTextAnimation.delayRange.lowerBound)...CGFloat(RecordingTextAnimation.delayRange.upperBound),
                        format: .seconds
                    )
                    .disabled(animation.unit == .all)
                    .help("Time between one word or letter starting and the next")
                }
                .disabled(animation.effect == .none && animation.unit == .all)

                StudioInspectorPickerRow("Easing", selection: Binding(
                    get: { animation.ease },
                    set: { ease in editAnimation("Change Text Animation") { $0.ease = ease } }
                )) {
                    ForEach(RecordingTextAnimation.Ease.allCases, id: \.self) { ease in
                        Text(ease.title).tag(ease)
                    }
                }
                .disabled(animation.effect == .none)
            }
        }
    }

    private var animation: RecordingTextAnimation {
        side == .enter ? text.animationIn : text.animationOut
    }

    private func edit(_ action: String, _ change: (inout RecordingTextOverlay) -> Void) {
        var edited = text
        change(&edited)
        model.editText(edited, actionName: action)
    }

    private func editAnimation(_ action: String, _ change: (inout RecordingTextAnimation) -> Void) {
        edit(action) { overlay in
            if side == .enter {
                change(&overlay.animationIn)
            } else {
                change(&overlay.animationOut)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RecordingTextOverlay, Value>, action: String) -> Binding<Value> {
        Binding(
            get: { text[keyPath: keyPath] },
            set: { value in edit(action) { $0[keyPath: keyPath] = value } }
        )
    }

    private func animationBinding(_ keyPath: WritableKeyPath<RecordingTextAnimation, TimeInterval>) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(animation[keyPath: keyPath]) },
            set: { value in editAnimation("Change Text Animation") { $0[keyPath: keyPath] = Double(value) } }
        )
    }
}

private struct StudioTextEffectTile: View {
    let text: RecordingTextOverlay
    let isExit: Bool
    let effect: RecordingTextAnimation.Effect
    let isSelected: Bool
    let onPick: () -> Void

    @State private var isHovering = false
    @State private var hoverStart = Date()
    @Environment(\.colorScheme) private var colorScheme

    private static let previewLength: TimeInterval = 100
    private static let hold: TimeInterval = 0.6

    var body: some View {
        VStack(spacing: 4) {
            InspectorTile(title: effect.title, aspectRatio: 1.6, isSelected: isSelected, action: onPick) {
                TimelineView(.animation(paused: !isHovering)) { context in
                    Canvas { graphics, size in
                        graphics.withCGContext { cgContext in
                            draw(in: cgContext, size: size, elapsed: context.date.timeIntervalSince(hoverStart))
                        }
                    }
                }
                .background(Color.primary.opacity(0.05))
                .onHover { hovering in
                    if hovering { hoverStart = Date() }
                    isHovering = hovering
                }
            }
            Text(effect.title)
                .font(.dsCaption)
                .foregroundStyle(isSelected ? Palette.label : Palette.secondaryLabel)
                .lineLimit(1)
        }
    }

    private func draw(in context: CGContext, size: CGSize, elapsed: TimeInterval) {
        var animation = isExit ? text.animationOut : text.animationIn
        animation.effect = effect
        if animation.unit != .all { animation.delay = min(animation.delay, 0.12) }

        var preview = text
        preview.text = "Text"
        preview.center = CGPoint(x: 0.5, y: 0.5)
        preview.fontSize = 0.3
        preview.hasBackground = false
        preview.color = colorScheme == .dark ? .white : RecordingOverlayColor(red: 0.1, green: 0.1, blue: 0.11)
        let still = RecordingTextAnimation(effect: .none)

        if isHovering {
            let span = animation.span(units: 4)
            let tau = elapsed.truncatingRemainder(dividingBy: span + Self.hold * 2)
            preview.animationIn = isExit ? still : animation
            preview.animationOut = isExit ? animation : still
            let local = isExit ? Self.previewLength - span - Self.hold + tau : tau
            RecordingTextOverlayRenderer.draw(
                preview, local: local, length: Self.previewLength,
                canvasSize: size, in: context, castsShadow: false
            )
        } else {
            var rest = animation
            rest.unit = .all
            rest.ease = .linear
            rest.duration = 1
            preview.animationIn = isExit ? still : rest
            preview.animationOut = isExit ? rest : still
            let progress = effect == .none ? 0 : 0.4
            let local = isExit ? Self.previewLength - 1 + progress : progress
            RecordingTextOverlayRenderer.draw(
                preview, local: local, length: Self.previewLength,
                canvasSize: size, in: context, castsShadow: false
            )
        }
    }
}

struct StudioRedactionInspectorControls: View {
    @Bindable var model: RecordingStudioModel
    let redaction: RecordingRedaction

    var body: some View {
        StudioInspectorGroup("Effect") {
            StudioInspectorModeSwitchRow(
                "Style",
                selection: Binding(
                    get: { redaction.style },
                    set: { style in edit("Change Pixelate Style") { $0.style = style } }
                ),
                options: RecordingRedaction.Style.allCases.map {
                    InterfaceModeSwitchOption(value: $0, title: $0.title, systemImage: $0.systemImage)
                }
            )

            InspectorFieldPair {
                InspectorSlider(
                    "Strength",
                    value: Binding(
                        get: { CGFloat(redaction.amount) },
                        set: { value in edit("Change Pixelate Strength") { $0.amount = Double(value) } }
                    ),
                    range: 0...1,
                    format: .percent()
                )
            } trailing: {
                InspectorSlider(
                    "Corners",
                    value: Binding(
                        get: { CGFloat(redaction.cornerRadius) },
                        set: { value in edit("Change Pixelate Corners") { $0.cornerRadius = Double(value) } }
                    ),
                    range: CGFloat(RecordingRedaction.cornerRadiusRange.lowerBound)...CGFloat(RecordingRedaction.cornerRadiusRange.upperBound),
                    format: .pixels
                )
                .help("Corner radius, measured on a 1080p picture")
            }

            InspectorFieldPair {
                InspectorSlider(
                    "Fade in",
                    value: fadeBinding(\.fadeIn),
                    range: CGFloat(RecordingRedaction.fadeRange.lowerBound)...CGFloat(RecordingRedaction.fadeRange.upperBound),
                    format: .seconds
                )
            } trailing: {
                InspectorSlider(
                    "Fade out",
                    value: fadeBinding(\.fadeOut),
                    range: CGFloat(RecordingRedaction.fadeRange.lowerBound)...CGFloat(RecordingRedaction.fadeRange.upperBound),
                    format: .seconds
                )
            }
        }
        .help("Drag the box on the paused canvas to move it, or its handles to resize it")
    }

    private func edit(_ action: String, _ change: (inout RecordingRedaction) -> Void) {
        var edited = redaction
        change(&edited)
        model.editRedaction(edited, actionName: action)
    }

    private func fadeBinding(_ keyPath: WritableKeyPath<RecordingRedaction, TimeInterval>) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(redaction[keyPath: keyPath]) },
            set: { value in edit("Change Pixelate Fade") { $0[keyPath: keyPath] = Double(value) } }
        )
    }
}

struct StudioImageInspectorControls: View {
    @Bindable var model: RecordingStudioModel
    let image: RecordingImageOverlay

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            StudioInspectorGroup("Appearance") {
                InspectorFieldPair {
                    InspectorSlider(
                        "Size",
                        value: value(\.width, action: "Resize Image"),
                        range: CGFloat(RecordingImageOverlay.widthRange.lowerBound)...CGFloat(RecordingImageOverlay.widthRange.upperBound),
                        format: .percent()
                    )
                    .help("Width as a share of the video's width")
                } trailing: {
                    InspectorSlider("Opacity", value: value(\.opacity, action: "Change Image Opacity"), range: 0...1, format: .percent())
                }
                InspectorFieldPair {
                    InspectorSlider(
                        "Rotation",
                        value: value(\.rotation, action: "Rotate Image"),
                        range: -180...180,
                        format: .degrees(signed: true)
                    )
                } trailing: {
                    InspectorSlider(
                        "Corners",
                        value: value(\.cornerRadius, action: "Change Image Corners"),
                        range: CGFloat(RecordingImageOverlay.cornerRadiusRange.lowerBound)...CGFloat(RecordingImageOverlay.cornerRadiusRange.upperBound),
                        format: .pixels
                    )
                    .help("Corner radius, measured on a 1080p video")
                }
                InspectorHalfField {
                    InspectorSlider("Shadow", value: value(\.shadow, action: "Change Image Shadow"), range: 0...1, format: .percent())
                }
            }

            StudioInspectorGroup("Fades") {
                InspectorFieldPair {
                    InspectorSlider(
                        "In",
                        value: value(\.fadeIn, action: "Change Image Fade"),
                        range: CGFloat(RecordingImageOverlay.fadeRange.lowerBound)...CGFloat(RecordingImageOverlay.fadeRange.upperBound),
                        format: .seconds
                    )
                } trailing: {
                    InspectorSlider(
                        "Out",
                        value: value(\.fadeOut, action: "Change Image Fade"),
                        range: CGFloat(RecordingImageOverlay.fadeRange.lowerBound)...CGFloat(RecordingImageOverlay.fadeRange.upperBound),
                        format: .seconds
                    )
                }
            }
        }
    }

    private func edit(_ action: String, _ change: (inout RecordingImageOverlay) -> Void) {
        var edited = image
        change(&edited)
        model.editImage(edited, actionName: action)
    }

    private func value(_ keyPath: WritableKeyPath<RecordingImageOverlay, Double>, action: String) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(image[keyPath: keyPath]) },
            set: { value in edit(action) { $0[keyPath: keyPath] = Double(value) } }
        )
    }
}

struct StudioAudioClipInspectorControls: View {
    @Bindable var model: RecordingStudioModel
    let clip: RecordingAudioClip

    var body: some View {
        StudioInspectorGroup("Sound") {
            InterfaceRow("Plays") {
                Text("\(Self.clock(clip.duration)) of \(Self.clock(clip.fileDuration)), from \(Self.clock(clip.start))")
                    .font(.dsFieldNumeric)
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .help("Drag its edges on the timeline to trim it. It stays put when the recording is cut.")

            InspectorHalfField {
                InspectorSlider("Volume", value: value(\.volume, action: "Change Audio Volume"), range: 0...1, format: .percent())
            }
            InspectorFieldPair {
                InspectorSlider(
                    "Fade in",
                    value: value(\.fadeIn, action: "Change Audio Fade"),
                    range: CGFloat(RecordingAudioClip.fadeRange.lowerBound)...CGFloat(RecordingAudioClip.fadeRange.upperBound),
                    format: .seconds
                )
            } trailing: {
                InspectorSlider(
                    "Fade out",
                    value: value(\.fadeOut, action: "Change Audio Fade"),
                    range: CGFloat(RecordingAudioClip.fadeRange.lowerBound)...CGFloat(RecordingAudioClip.fadeRange.upperBound),
                    format: .seconds
                )
            }
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, seconds)
        return total < 60 ? String(format: "%.1fs", total) : String(format: "%d:%04.1f", Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
    }

    private func value(_ keyPath: WritableKeyPath<RecordingAudioClip, Double>, action: String) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(clip[keyPath: keyPath]) },
            set: { value in
                var edited = clip
                edited[keyPath: keyPath] = Double(value)
                model.editAudioClip(edited, actionName: action)
            }
        )
    }
}
