import SwiftUI

struct ScreenshotOutputSettingsSection: View {
    @AppStorage(UpshotPreferences.screenshotConvertToSRGBKey) private var convertToSRGB = false
    @AppStorage(UpshotPreferences.screenshotScaleToOneXKey) private var scaleToOneX = false
    @AppStorage(UpshotPreferences.screenshotBorderKey) private var border = false
    @AppStorage(UpshotPreferences.screenshotRetinaSuffixKey) private var retinaSuffix = false

    var body: some View {
        Section("Screenshot Output") {
            Toggle("Convert to sRGB", isOn: $convertToSRGB)
                .toggleStyle(.ink)
            Toggle("Scale Retina screenshots to 1x", isOn: $scaleToOneX)
                .toggleStyle(.ink)
            Toggle("Add a 1px border", isOn: $border)
                .toggleStyle(.ink)
            Toggle("Add @2x to Retina filenames", isOn: $retinaSuffix)
                .toggleStyle(.ink)
        }
    }
}
