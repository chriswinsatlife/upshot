import SwiftUI

struct QuickAccessSettingsSection: View {
    @AppStorage(UpshotPreferences.previewOverlaySizeKey) private var overlaySize = QuickAccessOverlaySize.small
    @AppStorage(UpshotPreferences.previewAutoCloseActionKey) private var autoCloseAction = QuickAccessAutoCloseAction.close
    @AppStorage(UpshotPreferences.previewCloseAfterUploadingKey) private var closeAfterUploading = false
    @AppStorage(UpshotPreferences.previewSwipeTowardEdgeActionKey) private var swipeTowardEdgeAction = QuickAccessSwipeAction.tuck
    @AppStorage(UpshotPreferences.previewSwipeAwayFromEdgeActionKey) private var swipeAwayFromEdgeAction = QuickAccessSwipeAction.none

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
            Toggle("Close after uploading", isOn: $closeAfterUploading)
                .toggleStyle(.ink)
            Text("Hover over a card: C copies, S saves, E edits, P pins a screenshot, Delete closes, and Space opens Quick Look. Hold Option while dragging to keep the card.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Swipe toward screen edge", selection: $swipeTowardEdgeAction) {
                ForEach(QuickAccessSwipeAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            Picker("Swipe away from screen edge", selection: $swipeAwayFromEdgeAction) {
                ForEach(QuickAccessSwipeAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            Text("Two-finger horizontal swipes act on the card where the swipe starts. Swiping away from the tucked shelf always opens the shelf.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
