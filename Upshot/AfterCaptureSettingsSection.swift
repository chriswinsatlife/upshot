import SwiftUI

struct AfterCaptureActionsSection: View {
    let type: AfterCaptureType
    let title: String

    var body: some View {
        InterfaceSection(title) {
            ForEach(AfterCaptureAction.actions(for: type)) { action in
                AfterCaptureToggleRow(action: action, type: type)
            }
        }
    }
}

private struct AfterCaptureToggleRow: View {
    @AppStorage private var isOn: Bool
    private let title: String
    private let subtitle: String
    private let action: AfterCaptureAction
    private let type: AfterCaptureType

    init(action: AfterCaptureAction, type: AfterCaptureType) {
        _isOn = AppStorage(wrappedValue: action.defaultValue, action.storageKey(for: type))
        self.action = action
        self.type = type
        title = action.title
        subtitle = action.subtitle
    }

    var body: some View {
        if type == .recording {
            recordingRow
        } else {
            screenshotRow
        }
    }

    private var isCloudConfigured: Bool { CloudCredentialStore.shared.isConfigured }

    private var recordingRow: some View {
        let needsCloud = action == .upload && !isCloudConfigured
        return InterfaceRow(title, detail: needsCloud && isOn ? "Paused until Cloud is set up." : nil) {
            if needsCloud {
                InterfaceActionButton("Set Up Cloud…") { SettingsWindowController.show(tab: .cloud) }
            }
            Toggle(isOn: $isOn) { EmptyView() }
                .fixedSize()
                .accessibilityLabel(title)
                .disabled(needsCloud && !isOn)
        }
    }

    @ViewBuilder
    private var screenshotRow: some View {
        Toggle(isOn: $isOn) {
            InterfaceRowLabel(title, detail: subtitle)
        }
        .toggleStyle(.ink)
        .disabled(action == .upload && !isOn && !CloudCredentialStore.shared.isConfigured)

        if action == .upload && !CloudCredentialStore.shared.isConfigured {
            HStack {
                Text(isOn ? "Automatic uploads are paused until Cloud is set up."
                          : "Set up Cloud to enable automatic uploads.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                InterfaceActionButton("Set Up Cloud…") { SettingsWindowController.show(tab: .cloud) }
            }
        }
    }
}
