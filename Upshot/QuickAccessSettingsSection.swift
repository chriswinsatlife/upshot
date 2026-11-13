import SwiftUI

struct QuickAccessSettingsSection: View {
    @AppStorage(UpshotPreferences.previewOverlaySizeKey) private var overlaySize = QuickAccessOverlaySize.small

    var body: some View {
        Section("Quick Access") {
            Picker("Overlay size", selection: $overlaySize) {
                ForEach(QuickAccessOverlaySize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
        }
    }
}
