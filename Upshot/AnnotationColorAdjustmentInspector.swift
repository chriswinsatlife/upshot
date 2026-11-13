import SwiftUI

struct AnnotationColorAdjustmentInspector: View {
    @Binding var settings: AnnotationColorAdjustments

    var body: some View {
        InspectorSection("Color Adjustments") {
            InspectorSlider("Exposure", value: $settings.exposure, range: -3...3, format: .decimal(fractionDigits: 2))
            InspectorSlider("Contrast", value: $settings.contrast, range: 0...2, format: .percent())
            InspectorSlider("Saturation", value: $settings.saturation, range: 0...2, format: .percent())
            InspectorSlider("Temperature", value: $settings.temperature, range: -100...100, format: .integer)
            if !settings.isDefault {
                Button("Reset Color Adjustments") { settings = AnnotationColorAdjustments() }
            }
        }
    }
}
