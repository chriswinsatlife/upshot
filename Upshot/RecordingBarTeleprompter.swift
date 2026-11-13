import AppKit
import SwiftUI

struct RecordingBarTeleprompter: View {
    static let height: CGFloat = 252

    @AppStorage(UpshotPreferences.recordingTeleprompterEnabledKey) private var isEnabled = false
    @AppStorage(UpshotPreferences.recordingTeleprompterScriptKey) private var script = ""
    @AppStorage(UpshotPreferences.recordingTeleprompterLineCountKey) private var lineCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Space.m)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xs)

            InterfaceFlyoutDivider()

            editor

            InterfaceFlyoutDivider()

            footer
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
        }
        .frame(height: Self.height)
        .onChange(of: isEnabled) { _, enabled in
            if enabled {
                TeleprompterController.shared.preflightAssets()
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            Text("Teleprompter")
                .font(.dsHeadline)
                .foregroundStyle(Palette.label)
            Spacer(minLength: Space.m)
            Toggle("Show While Recording", isOn: $isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("Show While Recording")
        }
        .frame(height: InterfaceMetrics.modeSwitchHeight)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $script)
                .font(.dsBody)
                .lineSpacing(3)
                .foregroundStyle(Palette.label)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Space.xs)
                .padding(.vertical, Space.s)

            if script.isEmpty {
                Text("Type or paste your script")
                    .font(.dsBody)
                    .foregroundStyle(Palette.tertiaryLabel)
                    .padding(.top, Space.s)
                    .padding(.leading, Space.ml)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            Text(readingSummary)
                .font(.dsCaption)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryLabel)
                .contentTransition(.numericText())

            Spacer(minLength: Space.m)

            HStack(spacing: Space.s) {
                Text("Lines")
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                InterfaceModeSwitch(
                    "Lines",
                    selection: $lineCount,
                    options: UpshotPreferences.teleprompterLineCountRange.map {
                        InterfaceModeSwitchOption(value: $0, title: "\($0)")
                    },
                    surface: .window
                )
            }
            .help("Lines shown at once")
        }
    }

    private var readingSummary: String {
        let words = script.split { $0.isWhitespace || $0.isNewline }.count
        guard words > 0 else { return "No script" }
        let seconds = Int((Double(words) / 150 * 60).rounded())
        let time: String
        if seconds < 60 {
            time = "\(max(seconds, 1)) s"
        } else if seconds % 60 == 0 {
            time = "\(seconds / 60) min"
        } else {
            time = "\(seconds / 60) min \(seconds % 60) s"
        }
        return "\(words) word\(words == 1 ? "" : "s") · about \(time)"
    }
}
