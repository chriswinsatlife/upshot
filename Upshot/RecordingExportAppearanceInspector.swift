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
