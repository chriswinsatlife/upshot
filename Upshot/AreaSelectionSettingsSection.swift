import SwiftUI

struct AreaSelectionSettingsSection: View {
    @AppStorage(UpshotPreferences.areaSelectionFreezeScreenKey) private var freezeScreen = true

    @AppStorage(UpshotPreferences.areaSelectionCrosshairKey) private var crosshair = true
    @AppStorage(UpshotPreferences.areaSelectionMagnifierKey) private var magnifier = true

    var body: some View {
        Section("Area Selection") {
            Toggle("Freeze screen during selection", isOn: $freezeScreen)
            Toggle("Show crosshair", isOn: $crosshair)
            Toggle("Show pixel magnifier", isOn: $magnifier)
            Text("With a self-timer, the screen is captured after the countdown finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
