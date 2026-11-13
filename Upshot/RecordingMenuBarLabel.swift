import SwiftUI

struct RecordingMenuBarLabel: View {
    @State private var manager = ScreenRecordingManager.shared

    var body: some View {
        if let elapsed = manager.menuBarTimerText {
            Label {
                Text(elapsed)
                    .monospacedDigit()
            } icon: {
                Image(systemName: manager.state == .paused ? "pause.circle.fill" : "record.circle.fill")
            }
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(manager.state == .paused
                ? "Recording paused at \(elapsed)"
                : "Recording, \(elapsed) elapsed")
        } else {
            Image("MenuBarIcon")
                .accessibilityLabel("Upshot")
        }
    }
}
