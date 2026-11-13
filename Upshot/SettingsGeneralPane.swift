import AppKit
import ServiceManagement
import SwiftUI

struct SettingsGeneralPane: View {
    @AppStorage(UpshotPreferences.exportDirectoryPathKey) private var exportDirectoryPath = ""
    @AppStorage(UpshotPreferences.playSoundsKey) private var playSounds = true
    @AppStorage(UpshotPreferences.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(UpshotPreferences.hideDockIconKey) private var hideDockIcon = false
    @State private var launchAtLoginStatus = LaunchAtLoginController.status
    @State private var launchAtLoginError: String?

    @Environment(SettingsPermissions.self) private var permissions

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginStatus.isEnabled },
            set: updateLaunchAtLogin
        )
    }

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { !hideDockIcon },
            set: { hideDockIcon = !$0 }
        )
    }

    private var launchAtLoginDetail: String? {
        if let launchAtLoginError { return launchAtLoginError }
        if launchAtLoginStatus.requiresApproval { return "Approve Upshot in System Settings › General › Login Items." }
        return nil
    }

    var body: some View {
        InterfaceFormPage {
            InterfaceSection("App") {
                Toggle(isOn: launchAtLoginBinding) {
                    InterfaceRowLabel("Launch at login", detail: launchAtLoginDetail, detailIsCritical: launchAtLoginError != nil)
                }
                .frame(minHeight: InterfaceMetrics.rowMinimumHeight)

                InterfaceToggleRow("Show menu bar icon", isOn: $showMenuBarIcon)
                InterfaceToggleRow("Show Dock icon", isOn: showDockIconBinding)
                InterfaceToggleRow("Play sounds", isOn: $playSounds)
            }

            InterfaceSection("Export") {
                InterfaceFolderRow(
                    "Export folder",
                    folderURL: UpshotPreferences.exportDirectory,
                    onReset: exportDirectoryPath.isEmpty ? nil : { exportDirectoryPath = "" },
                    onChoose: chooseExportDirectory
                )
            }

            InterfaceSection("Permissions") {
                ForEach(SettingsPermissions.Kind.allCases) { kind in
                    SettingsPermissionRow(kind: kind, permissions: permissions)
                }
            }
        }
        .onAppear(perform: refreshLaunchAtLoginStatus)
        .onChange(of: hideDockIcon) { _, _ in
            AppActivationPolicy.dockIconPreferenceDidChange()
        }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = UpshotPreferences.exportDirectory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportDirectoryPath = url.path
        AppLog.event("settings", "export_folder_changed", fields: ["path": url.abbreviatedPath])
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LaunchAtLoginController.status
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            launchAtLoginError = nil
            try LaunchAtLoginController.setEnabled(isEnabled)
            AppLog.event("settings", "launch_at_login_changed", fields: ["enabled": String(isEnabled), "outcome": "success"])
        } catch {
            launchAtLoginError = "Could not update Launch at Login: \(error.localizedDescription)"
            AppLog.event("settings", "launch_at_login_changed", fields: ["enabled": String(isEnabled), "outcome": "failed", "error": AppLog.error(error)])
        }

        refreshLaunchAtLoginStatus()
    }
}

private enum LaunchAtLoginStatus {
    case disabled
    case enabled
    case requiresApproval

    var isEnabled: Bool {
        self == .enabled
    }

    var requiresApproval: Bool {
        self == .requiresApproval
    }
}

@MainActor
private enum LaunchAtLoginController {
    static var status: LaunchAtLoginStatus {
        if UpshotStorage.isRenderingStates {
            return StateRenderer.scenario.hasSuffix("-expanded") ? .requiresApproval : .disabled
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    static func setEnabled(_ isEnabled: Bool) throws {
        let service = SMAppService.mainApp

        if isEnabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}
