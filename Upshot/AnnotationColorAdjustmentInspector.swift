import SwiftUI

struct AnnotationColorAdjustmentInspector: View {
    @Binding var settings: AnnotationColorAdjustments
    var onEditorAction: () -> Void = {}

    var body: some View {
        Section {
            Group {
                AnnotationInspectorSliderRow("Exposure", value: $settings.exposure, range: -3...3, format: .decimal(fractionDigits: 2))
                AnnotationInspectorSliderRow("Contrast", value: $settings.contrast, range: 0...2, format: .percent())
                AnnotationInspectorSliderRow("Saturation", value: $settings.saturation, range: 0...2, format: .percent())
                AnnotationInspectorSliderRow("Temperature", value: $settings.temperature, range: -100...100, format: .integer)
            }
            .annotationInspectorSliderLabels(["Exposure", "Contrast", "Saturation", "Temperature"])
        } header: {
            HStack(spacing: Space.s) {
                InterfaceSectionHeader("Color adjustments")
                Spacer(minLength: 0)
                if !settings.isDefault {
                    InterfaceResetButton(help: "Reset color adjustments") {
                        onEditorAction()
                        settings = AnnotationColorAdjustments()
                    }
                }
            }
        }
    }
}
