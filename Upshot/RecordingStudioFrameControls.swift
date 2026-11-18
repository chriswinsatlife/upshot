import SwiftUI

struct RecordingStudioFrameControls: View {
    @Bindable var model: RecordingStudioModel
    @State private var showsAdvancedPadding = false
    @State private var removedBackground: BackgroundSnapshot?

    private struct BackgroundSnapshot {
        let aspect: ExportAspectPreset
        let mode: ExportAspectContentMode
        let padding: CGFloat
        let sides: RecordingStudioPadding?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            InterfaceToggleRow("Remove background", isOn: Binding(
                get: { model.exportAspect == .original && model.style.resolvedPaddingSides.isZero },
                set: removeBackground
            ))
            InterfaceToggleRow("Advanced", isOn: Binding(
                get: { showsAdvancedPadding },
                set: { value in
                    showsAdvancedPadding = value
                    AppLog.event("recording", "studio_padding_advanced_changed", fields: ["enabled": String(value)])
                }
            ))
            if showsAdvancedPadding {
                InterfaceToggleRow("Link padding sides", isOn: Binding(
                    get: { model.style.resolvedPaddingSides.linked },
                    set: { linked in
                        var sides = model.style.resolvedPaddingSides
                        sides.setLinked(linked)
                        model.style.paddingSides = sides
                        AppLog.event("recording", "studio_padding_link_changed", fields: ["linked": String(linked)])
                    }
                ))
            }
            if model.style.resolvedPaddingSides.linked {
                InspectorFieldPair {
                    InspectorSlider("Padding", value: paddingBinding(\.top), range: 0...100, format: paddingFormat)
                } trailing: {
                    InspectorSlider("Corners", value: $model.style.cornerRadius, range: 0...0.08, format: .percent())
                }
            } else {
                InspectorFieldPair {
                    InspectorSlider("Top", value: paddingBinding(\.top), range: 0...250, format: paddingFormat)
                } trailing: {
                    InspectorSlider("Bottom", value: paddingBinding(\.bottom), range: 0...250, format: paddingFormat)
                }
                InspectorFieldPair {
                    InspectorSlider("Left", value: paddingBinding(\.left), range: 0...100, format: paddingFormat)
                } trailing: {
                    InspectorSlider("Right", value: paddingBinding(\.right), range: 0...100, format: paddingFormat)
                }
                InspectorHalfField {
                    InspectorSlider("Corners", value: $model.style.cornerRadius, range: 0...0.08, format: .percent())
                }
            }
            InspectorHalfField {
                InspectorSlider("Shadow", value: Binding(
                    get: { model.style.shadow },
                    set: { value in
                        model.style.usesLayeredShadow = true
                        model.style.shadow = (value * 100).rounded() / 100
                        AppLog.event("recording", "studio_shadow_changed", fields: ["intensity": String(Double(model.style.shadow))])
                    }
                ), range: 0...1, format: .percent())
                .disabled(model.style.background == .none)
            }
        }
    }

    private var paddingFormat: InspectorValueFormat {
        InspectorValueFormat(multiplier: 1, fractionDigits: 0, suffix: "%", showsPositiveSign: false,
                             step: 1, acceptedSuffixes: ["%"])
    }

    private func paddingBinding(_ side: WritableKeyPath<RecordingStudioPadding, CGFloat>) -> Binding<CGFloat> {
        Binding(get: { model.style.resolvedPaddingSides[keyPath: side] }, set: { value in
            var sides = model.style.resolvedPaddingSides
            if sides.linked {
                sides = RecordingStudioPadding(uniform: value.rounded())
            } else {
                sides[keyPath: side] = value.rounded()
            }
            model.style.paddingSides = sides.normalized
            AppLog.event("recording", "studio_padding_changed", fields: [
                "top": String(Double(sides.top)), "bottom": String(Double(sides.bottom)),
                "left": String(Double(sides.left)), "right": String(Double(sides.right))
            ])
        })
    }

    private func removeBackground(_ remove: Bool) {
        if remove {
            removedBackground = BackgroundSnapshot(aspect: model.exportAspect, mode: model.exportAspectMode,
                                                   padding: model.style.padding, sides: model.style.paddingSides)
            let linked = model.style.resolvedPaddingSides.linked
            model.exportAspect = .original
            model.exportAspectMode = .fill
            model.style.paddingSides = RecordingStudioPadding(top: 0, bottom: 0, left: 0, right: 0, linked: linked)
            model.style.padding = 0
        } else if let snapshot = removedBackground {
            model.exportAspect = snapshot.aspect
            model.exportAspectMode = snapshot.mode
            model.style.padding = snapshot.padding
            model.style.paddingSides = snapshot.sides
            removedBackground = nil
        } else {
            model.style.padding = 0.06
            model.style.paddingSides = nil
        }
        AppLog.event("recording", "studio_background_removal_changed", fields: ["enabled": String(remove)])
    }
}
