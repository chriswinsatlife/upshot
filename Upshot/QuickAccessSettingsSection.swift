import SwiftUI

struct QuickAccessSettingsSection: View {
    @AppStorage(UpshotPreferences.previewOverlaySizeKey) private var overlaySize = QuickAccessOverlaySize.small
    @AppStorage(UpshotPreferences.previewAutoCloseActionKey) private var autoCloseAction = QuickAccessAutoCloseAction.close

    var body: some View {
        Section("Quick Access") {
            Picker("Overlay size", selection: $overlaySize) {
                ForEach(QuickAccessOverlaySize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            Picker("When auto-close ends", selection: $autoCloseAction) {
                ForEach(QuickAccessAutoCloseAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            Text("Save and Close saves to the configured export folder. Failed saves or copies keep the card open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
