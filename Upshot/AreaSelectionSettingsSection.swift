import SwiftUI

struct AreaSelectionSettingsSection: View {
    @AppStorage(UpshotPreferences.areaSelectionFreezeScreenKey) private var freezeScreen = true

    var body: some View {
        Section("Area Selection") {
            Toggle("Freeze screen during selection", isOn: $freezeScreen)
            Text("With a self-timer, the screen is captured after the countdown finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
