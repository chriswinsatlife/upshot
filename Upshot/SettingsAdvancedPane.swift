import SwiftUI

struct SettingsAdvancedPane: View {
    var body: some View {
        InterfaceFormPage {
            CaptureHistorySettingsSection()
            AutomationSettingsSection()
        }
    }
}
