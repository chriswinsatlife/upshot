import SwiftUI

struct SettingsShortcutsPane: View {
    var body: some View { InterfaceFormPage { CaptureHotkeySettingsSection(actions: CaptureHotkeyAction.allCases) } }
}

struct SettingsQuickAccessPane: View {
    var body: some View { OverlaySettingsPane() }
}

struct SettingsScreenRecordingPane: View {
    var body: some View { VideoSettingsPane() }
}

struct SettingsAnnotatePane: View {
    var body: some View { InterfaceFormPage { AnnotationEditorSettingsSection() } }
}

struct SettingsTextRecognitionPane: View {
    var body: some View { InterfaceFormPage { TextRecognitionSettingsSection() } }
}

struct SettingsAdvancedPane: View {
    var body: some View {
        InterfaceFormPage {
            CaptureHistorySettingsSection()
            AutomationSettingsSection()
        }
    }
}
