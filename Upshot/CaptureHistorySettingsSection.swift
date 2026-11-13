import SwiftUI

struct CaptureHistorySettingsSection: View {
    @AppStorage(UpshotPreferences.historyRetentionDaysKey) private var retentionDays = 0

    private static let presetRetentionDays = [0, 1, 3, 7, 14, 30]

    private var keptRetentionDays: Int { max(0, retentionDays) }

    private var retentionDaysBinding: Binding<Int> {
        Binding(
            get: { keptRetentionDays },
            set: { retentionDays = max(0, $0) }
        )
    }

    private var retentionDayOptions: [Int] {
        guard !Self.presetRetentionDays.contains(keptRetentionDays) else { return Self.presetRetentionDays }
        return (Self.presetRetentionDays + [keptRetentionDays]).sorted { first, second in
            first == 0 || (second != 0 && first < second)
        }
    }

    var body: some View {
        InterfaceSection("Capture History") {
            InterfacePickerRow(
                "Keep history",
                detail: keptRetentionDays > 0 ? "Older captures move to the Trash." : nil,
                selection: retentionDaysBinding
            ) {
                ForEach(retentionDayOptions, id: \.self) { days in
                    Text(Self.retentionTitle(days: days)).tag(days)
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button("Open Capture History", action: CaptureHistoryActions.openCaptureHistory)
            }
            .frame(minHeight: InterfaceMetrics.rowMinimumHeight)
        }
        .motion(value: keptRetentionDays > 0)
        .onChange(of: retentionDays) { _, days in
            AppLog.event("library", "capture_history_retention_setting", fields: ["days": String(describing: max(0, days))])
            CaptureHistoryRetention.shared.scheduleCleanup()
        }
    }

    static func retentionTitle(days: Int) -> String {
        switch days {
        case 0: "Forever"
        case 1: "1 day"
        case 7: "1 week"
        case 14: "2 weeks"
        case 30: "1 month"
        default: "\(days) days"
        }
    }
}
