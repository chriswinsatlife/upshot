import SwiftUI

struct LiveRecordingSettingsSection: View {
    @AppStorage(UpshotPreferences.recordingDimOutsideAreaKey) private var dimOutsideArea = true

    var body: some View {
        Section("While Recording") {
            Toggle("Dim the screen outside the recorded area", isOn: $dimOutsideArea)
        }
    }
}
