import SwiftUI

struct AreaSelectionSettingsSection: View {
    @AppStorage(UpshotPreferences.areaSelectionFreezeScreenKey) private var freezeScreen = false
    @AppStorage(UpshotPreferences.areaSelectionCrosshairKey) private var crosshair = false
    @AppStorage(UpshotPreferences.areaSelectionMagnifierKey) private var magnifier = false

    var body: some View {
        InterfaceToggleRow("Freeze screen during selection", isOn: $freezeScreen)
        InterfaceToggleRow("Show crosshair", isOn: $crosshair)
        InterfaceToggleRow("Show magnifier", isOn: $magnifier)
    }
}
