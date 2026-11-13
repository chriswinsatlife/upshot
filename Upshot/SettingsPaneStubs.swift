import SwiftUI

struct SettingsShortcutsPane: View {
    var body: some View { InterfaceFormPage { CaptureHotkeySettingsSection(actions: CaptureHotkeyAction.allCases) } }
}
