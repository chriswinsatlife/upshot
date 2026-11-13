import SwiftUI

struct ScreenshotOutputSettingsSection: View {
    @AppStorage(UpshotPreferences.screenshotConvertToSRGBKey) private var convertToSRGB = false
    @AppStorage(UpshotPreferences.screenshotScaleToOneXKey) private var scaleToOneX = false

    var body: some View {
        Section("Screenshot Output") {
            Toggle("Convert to sRGB", isOn: $convertToSRGB)
                .toggleStyle(.ink)
            Toggle("Scale Retina screenshots to 1x", isOn: $scaleToOneX)
                .toggleStyle(.ink)
        }
    }
}
