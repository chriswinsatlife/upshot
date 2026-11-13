import SwiftUI

struct AnnotationCameraInspector: View {
    @Binding var settings: AnnotationCameraSettings
    let onEditorAction: () -> Void

    var body: some View {
        Group {
            slider("Tilt X", \.tiltXDegrees, range: -45...45, format: .degrees(signed: true))
            slider("Tilt Y", \.tiltYDegrees, range: -45...45, format: .degrees(signed: true))
            slider("Roll", \.rollDegrees, range: -45...45, format: .degrees(signed: true))
        }
        .help("Orbit the camera around the card center, then roll the view")

        Group {
            slider("Field of view", \.fieldOfViewDegrees, range: 18...80, format: .degrees())
            slider("Zoom", \.zoom, range: 0.4...2.5, format: .magnification(fractionDigits: 2))
            slider("Pan X", \.panX, range: -0.5...0.5, format: .percent(signed: true))
            slider("Pan Y", \.panY, range: -0.5...0.5, format: .percent(signed: true))
        }
        .help("Use a lower field of view for a calmer lens, then frame with Zoom and Pan")

        Group {
            slider("Rotate X", \.rotationXDegrees, range: -60...60, format: .degrees(signed: true))
            slider("Rotate Y", \.rotationYDegrees, range: -60...60, format: .degrees(signed: true))
        }
        .help("Rotate the card around its own horizontal and vertical center axes")
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<AnnotationCameraSettings, CGFloat>,
        range: ClosedRange<CGFloat>,
        format: InspectorValueFormat
    ) -> some View {
        AnnotationInspectorSliderRow(title, value: binding(keyPath), range: range, format: format)
    }

    private func binding(_ keyPath: WritableKeyPath<AnnotationCameraSettings, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                onEditorAction()
                var updatedSettings = settings
                updatedSettings.upgradeProjectionIfNeeded()
                updatedSettings[keyPath: keyPath] = value
                settings = updatedSettings
            }
        )
    }
}
