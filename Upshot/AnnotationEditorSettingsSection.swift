import SwiftUI

struct AnnotationEditorSettingsSection: View {
    @AppStorage(UpshotPreferences.annotationEditorAlwaysOnTopKey) private var alwaysOnTop = false

    @AppStorage(UpshotPreferences.annotationObjectShadowsKey) private var objectShadows = false

    var body: some View {
        Section("Annotation Editor") {
            Toggle("Keep editor above other windows", isOn: $alwaysOnTop)
            Toggle("Draw shadows on new annotations", isOn: $objectShadows)
        }
    }
}
