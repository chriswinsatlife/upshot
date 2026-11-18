import AppKit
import Foundation
import SwiftUI

struct StudioCaptionAppearanceControls: View {
    @Bindable var model: RecordingStudioModel

    var body: some View {
        StudioInspectorPickerRow("Style", selection: Binding(
            get: { model.subtitleStyle.preset },
            set: { model.subtitleStyle.apply($0) }
        )) {
            if model.subtitleStyle.preset == .upshot {
                Text("Upshot").tag(StudioCaptionPreset.upshot)
            }
            Text("Reveal").tag(StudioCaptionPreset.reveal)
            Text("Classic").tag(StudioCaptionPreset.serif)
        }

        if model.subtitleStyle.preset == .upshot {
            InspectorFieldPair {
                InspectorSlider("Position", value: value(\.verticalPosition), range: 0.1...0.95, format: .percent())
            } trailing: {
                InspectorSlider("Size", value: value(\.fontScale), range: 0.6...1.8, format: .magnification(fractionDigits: 1))
            }
            if model.hasTranscriptWords {
                InterfaceToggleRow("Highlight spoken word", isOn: $model.subtitleStyle.highlightsSpokenWord)
            }
        } else {
            InspectorSlider("Aa", value: value(\.fontSize, step: 1), range: 16...72, format: .pixels)
                .accessibilityLabel("Caption size")
            DisclosureGroup("Advanced") {
                StudioInspectorPickerRow("Animation", selection: Binding(
                    get: { model.subtitleStyle.animation },
                    set: { model.subtitleStyle.animation = $0 }
                )) {
                    ForEach(StudioCaptionAnimation.allCases, id: \.self) { animation in
                        Text(animation.title).tag(animation)
                    }
                }
                ColorPicker("Text color", selection: Binding(
                    get: { Color(cgColor: StudioCaptionColor.color(model.subtitleStyle.textColor)) },
                    set: { color in
                        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else {
                            AppLog.event("recording", "studio_caption_color_conversion_failed")
                            return
                        }
                        let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                        model.subtitleStyle.textColor = hex
                        model.subtitleStyle.inactiveTextColor = hex
                    }
                ), supportsOpacity: false)
                InspectorSlider("Rows", value: Binding(
                    get: { CGFloat(model.subtitleStyle.maximumRows) },
                    set: { model.subtitleStyle.maximumRows = min(4, max(1, Int($0.rounded()))) }
                ), range: 1...4, format: .integer)
                InspectorSlider("Bottom offset", value: percent(\.bottomOffset), range: 0...0.3, format: .percent())
                InspectorSlider("Max width", value: percent(\.maximumWidth), range: 0.4...0.95, format: .percent())
                InspectorSlider("Box radius", value: value(\.boxRadius, step: 0.5), range: 0...40, format: .decimal(fractionDigits: 1))
                InspectorSlider("Background opacity", value: value(\.backgroundOpacity, step: 0.01), range: 0...1, format: .percent())
                InterfaceToggleRow("Reveal words", isOn: $model.subtitleStyle.revealsWords)
                if model.hasTranscriptWords {
                    InterfaceToggleRow("Highlight spoken word", isOn: $model.subtitleStyle.highlightsSpokenWord)
                }
            }
        }
    }

    private func value(_ keyPath: WritableKeyPath<SubtitleBarStyle, Double>, step: Double? = nil) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(model.subtitleStyle[keyPath: keyPath]) },
            set: { value in
                let number = Double(value)
                model.subtitleStyle[keyPath: keyPath] = step.map { (number / $0).rounded() * $0 } ?? number
            }
        )
    }

    private func percent(_ keyPath: WritableKeyPath<SubtitleBarStyle, Double>) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(model.subtitleStyle[keyPath: keyPath] / 100) },
            set: { model.subtitleStyle[keyPath: keyPath] = Double(($0 * 100).rounded()) }
        )
    }
}
