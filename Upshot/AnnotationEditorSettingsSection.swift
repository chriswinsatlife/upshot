import SwiftUI

struct AnnotationEditorSettingsSection: View {
    @AppStorage(UpshotPreferences.annotationEditorAlwaysOnTopKey) private var alwaysOnTop = false

    var body: some View {
        Section("Annotation Editor") {
            Toggle("Keep editor above other windows", isOn: $alwaysOnTop)
        }
    }
}
