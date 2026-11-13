import SwiftUI

struct RecordingZoomAnimationStylePicker: View {
    @Bindable var model: RecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
            InspectorGroupLabel("Animation")
            InspectorSegmented(
                options: RecordingZoomAnimationStyle.allCases,
                isSelected: { $0 == model.exportAppearance.zoomAnimationStyle },
                onTap: { model.exportAppearance.zoomAnimationStyle = $0 },
                label: { Text($0.rawValue).font(.inspectorSegment) }
            )
        }
    }
}

struct RecordingKeystrokeAppearanceControls: View {
    @Bindable var model: RecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
            Picker("Size", selection: $model.exportAppearance.keystrokes.size) {
                ForEach(RecordingKeystrokeSize.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Style", selection: $model.exportAppearance.keystrokes.style) {
                ForEach(RecordingKeystrokeStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            ForEach(0..<3, id: \.self) { row in
                InspectorRow(["Top", "Middle", "Bottom"][row]) {
                    InspectorSegmented(
                        options: RecordingKeystrokePosition.allCases.filter { $0.row == row },
                        isSelected: { $0 == model.exportAppearance.keystrokes.resolvedPosition(fallback: model.keystrokePlacement) },
                        onTap: { model.exportAppearance.keystrokes.position = $0 },
                        label: { Text($0.columnTitle).font(.inspectorSegment) }
                    )
                }
            }
            Picker("Keys", selection: $model.exportAppearance.keystrokes.filter) {
                ForEach(RecordingKeystrokeFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            InspectorHint("Typed keys remain hidden with Command Keys Only. All Keys shows typed keys only when their capture was enabled before recording.")
        }
    }
}
