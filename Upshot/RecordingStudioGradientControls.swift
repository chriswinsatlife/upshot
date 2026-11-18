import SwiftUI

struct RecordingStudioGradientControls: View {
    @Bindable var model: RecordingStudioModel
    @State private var store = RecordingStudioGradientStore()
    @State private var draft = RecordingStudioGradient.initial
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if case .gradient = model.style.background {
                Button("Custom gradient") {
                    draft = selectedGradient ?? .initial
                    isEditing = true
                    AppLog.event("recording", "studio_gradient_editor_opened")
                }
                .buttonStyle(.interfaceAction)
            }
            ForEach(store.gradients, id: \.self) { gradient in
                HStack(spacing: Space.m) {
                    Button {
                        select(gradient)
                    } label: {
                        BackgroundSwatch(style: .gradient(gradient.backgroundGradient))
                            .frame(height: InspectorMetrics.controlHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select custom gradient")
                    Button("Remove") {
                        if selectedGradient == gradient {
                            model.style.authoredGradient = nil
                            if let first = AnnotationBackgroundGradient.presets.first { model.style.background = .gradient(first) }
                        }
                        store.remove(gradient)
                    }
                }
            }
        }
        .popover(isPresented: $isEditing) {
            VStack(alignment: .leading, spacing: Space.m) {
                InspectorSlider("Angle", value: Binding(
                    get: { CGFloat(draft.angle) },
                    set: {
                        draft.angle = Int($0.rounded())
                        AppLog.event("recording", "studio_gradient_angle_changed", fields: ["degrees": String(draft.angle)])
                    }
                ), range: 0...360, format: .degrees())
                ForEach(draft.colors.indices, id: \.self) { index in
                    HStack(spacing: Space.m) {
                        ColorPicker("Color \(index + 1)", selection: Binding(
                            get: { RecordingStudioGradient.color(draft.colors[index]).color },
                            set: {
                                draft.colors[index] = RecordingStudioGradient.hex($0)
                                AppLog.event("recording", "studio_gradient_color_changed", fields: ["stop": String(index)])
                            }
                        ), supportsOpacity: false)
                        if draft.colors.count > 2 {
                            Button("Remove") {
                                draft.colors.remove(at: index)
                                AppLog.event("recording", "studio_gradient_stop_removed", fields: ["stops": String(draft.colors.count)])
                            }
                        }
                    }
                }
                Button("Add color") {
                    draft.colors.append(RecordingStudioGradient.addedColor)
                    AppLog.event("recording", "studio_gradient_stop_added", fields: ["stops": String(draft.colors.count)])
                }
                    .disabled(draft.colors.count >= 5)
                HStack(spacing: Space.m) {
                    Button("Cancel") {
                        isEditing = false
                        AppLog.event("recording", "studio_gradient_editor_cancelled")
                    }
                    Button("Save") {
                        store.save(draft)
                        select(draft)
                        isEditing = false
                    }
                    .disabled(!draft.isValid)
                }
            }
            .padding(Space.l)
        }
    }

    private var selectedGradient: RecordingStudioGradient? {
        guard case .gradient(let background) = model.style.background else { return nil }
        if let gradient = model.style.authoredGradient,
           background == gradient.backgroundGradient { return gradient }
        return RecordingStudioGradient(backgroundGradient: background)
    }

    private func select(_ gradient: RecordingStudioGradient) {
        model.style.authoredGradient = gradient.normalized
        model.style.background = .gradient(gradient.normalized.backgroundGradient)
        AppLog.event("recording", "studio_gradient_selected", fields: ["stops": String(gradient.colors.count)])
    }
}
