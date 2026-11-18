import AppKit
import SwiftUI

struct RecordingClickEffectControls: View {
    @Bindable var model: RecordingStudioModel

    var body: some View {
        StudioInspectorPickerRow("Click effect", selection: Binding(
            get: { model.clickEffectSettings.effect },
            set: { effect in
                guard effect != model.clickEffectSettings.effect else { return }
                var settings = model.clickEffectSettings
                settings.effect = effect
                if effect != .none, effect != .impact {
                    settings.color = RecordingClickEffectSettings.defaultColor
                }
                model.clickEffectSettings = settings
            }
        )) {
            ForEach(RecordingClickEffect.allCases) { effect in
                Text(effect.title).tag(effect)
            }
        }
        if model.clickEffectSettings.effect != .none, model.clickEffectSettings.effect != .impact {
            DisclosureGroup("Advanced") {
                StudioInspectorPickerRow("Color", selection: $model.clickEffectSettings.color) {
                    ForEach(RecordingClickEffectSettings.palette, id: \.self) { color in
                        Text(color).tag(color)
                    }
                    if !RecordingClickEffectSettings.palette.contains(model.clickEffectSettings.color) {
                        Text(model.clickEffectSettings.color).tag(model.clickEffectSettings.color)
                    }
                }
                ColorPicker("Custom color", selection: Binding(
                    get: {
                        let rgb = model.clickEffectSettings.rgb
                        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                    },
                    set: { color in
                        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
                            AppLog.event("recording", "click_effect_color_failed")
                            return
                        }
                        model.clickEffectSettings.color = String(
                            format: "#%02X%02X%02X",
                            Int((rgb.redComponent * 255).rounded()),
                            Int((rgb.greenComponent * 255).rounded()),
                            Int((rgb.blueComponent * 255).rounded())
                        )
                    }
                ), supportsOpacity: false)
                InspectorSlider("Size", value: value(\.scale, step: 0.05), range: 0.5...2, format: .magnification(fractionDigits: 2))
                InspectorSlider("Opacity", value: value(\.opacity, step: 0.01), range: 0...1, format: .percent())
                InspectorSlider("Duration", value: value(\.duration, step: 0.01), range: 0.12...1.2, format: InspectorValueFormat(
                    multiplier: 1_000,
                    fractionDigits: 0,
                    suffix: " ms",
                    showsPositiveSign: false,
                    step: 0.01,
                    acceptedSuffixes: ["milliseconds", "ms"]
                ))
            }
        }
    }

    private func value(_ keyPath: WritableKeyPath<RecordingClickEffectSettings, Double>, step: Double) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(model.clickEffectSettings[keyPath: keyPath]) },
            set: { model.clickEffectSettings[keyPath: keyPath] = (Double($0) / step).rounded() * step }
        )
    }
}
