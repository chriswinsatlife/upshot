import SwiftUI

struct AnnotationEditorSettingsSection: View {
    @AppStorage(UpshotPreferences.annotationEditorAlwaysOnTopKey) private var alwaysOnTop = false

    @AppStorage(UpshotPreferences.annotationObjectShadowsKey) private var objectShadows = false

    @AppStorage(UpshotPreferences.annotationAutomaticallyExpandCanvasKey) private var automaticallyExpandCanvas = false

    var body: some View {
        Group {
            Toggle("Keep editor above other windows", isOn: $alwaysOnTop)
                .toggleStyle(.ink)
            Toggle("Draw shadows on new annotations", isOn: $objectShadows)
                .toggleStyle(.ink)
            Toggle("Expand canvas beyond the image edge", isOn: $automaticallyExpandCanvas)
                .toggleStyle(.ink)
        }
    }
}
