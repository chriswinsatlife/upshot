import SwiftUI

struct AreaSelectionSettingsSection: View {
    @AppStorage(UpshotPreferences.areaSelectionFreezeScreenKey) private var freezeScreen = true

    @AppStorage(UpshotPreferences.areaSelectionCrosshairKey) private var crosshair = true
    @AppStorage(UpshotPreferences.areaSelectionMagnifierKey) private var magnifier = true

    var body: some View {
        Section("Area Selection") {
            Toggle(isOn: $freezeScreen) {
                SettingsControlLabel("Freeze screen during selection", detail: "With a self-timer, capture after the countdown finishes.")
            }
            .toggleStyle(.ink)

            Toggle(isOn: $crosshair) {
                SettingsControlLabel("Show crosshair", detail: "Extend the selection cursor across the display. Toggle with X during selection.")
            }
            .toggleStyle(.ink)

            Toggle(isOn: $magnifier) {
                SettingsControlLabel("Show pixel magnifier", detail: "Magnify pixels beside the selection cursor. Toggle with M during selection.")
            }
            .toggleStyle(.ink)
        }
    }
}
