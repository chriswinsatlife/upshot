import SwiftUI

struct ScreenshotOutputSettingsSection: View {
    @AppStorage(UpshotPreferences.screenshotConvertToSRGBKey) private var convertToSRGB = false

    var body: some View {
        Section("Screenshot Output") {
            Toggle("Convert to sRGB", isOn: $convertToSRGB)
                .toggleStyle(.ink)
        }
    }
}
