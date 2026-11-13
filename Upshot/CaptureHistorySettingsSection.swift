import SwiftUI

struct CaptureHistorySettingsSection: View {
    @AppStorage(UpshotPreferences.historyRetentionDaysKey) private var retentionDays = 0

    var body: some View {
        Section {
            LabeledContent("Keep Capture History") {
                TextField("Days", value: Binding(
                    get: { max(0, retentionDays) },
                    set: { retentionDays = max(0, $0) }
                ), format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                Text("days")
                    .foregroundStyle(.secondary)
            }
            Button("Open Capture History", action: CaptureHistoryActions.openCaptureHistory)
        } header: {
            Text("Capture History")
        } footer: {
            Text("0 keeps captures indefinitely. Older captures and video projects move to Trash. Captures with an open editor are kept until a later cleanup after the editor closes. Saved copies outside the capture library are kept.")
        }
        .onChange(of: retentionDays) { _, days in
            AppLog.event("library", "capture_history_retention_setting", fields: ["days": String(describing: max(0, days))])
            CaptureHistoryRetention.shared.scheduleCleanup()
        }
    }
}
