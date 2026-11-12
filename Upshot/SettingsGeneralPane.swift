//
//  SettingsGeneralPane.swift
//  Upshot
//

import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsPane: View {
    @AppStorage(UpshotPreferences.exportDirectoryPathKey) private var exportDirectoryPath = ""
    @AppStorage(UpshotPreferences.saveButtonUsesFolderKey) private var saveButtonUsesFolder = false
    @AppStorage(UpshotPreferences.playSoundsKey) private var playSounds = true
    @AppStorage(UpshotPreferences.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(UpshotPreferences.hideDockIconKey) private var hideDockIcon = false
    @AppStorage(UpshotPreferences.includeAppWindowsInCapturesKey)
    private var includeAppWindowsInCaptures = false
    @AppStorage(UpshotPreferences.libraryAnalyzeCapturesKey) private var analyzeCaptures = true
    @AppStorage(UpshotPreferences.librarySortExistingKey) private var sortExistingCaptures = false
    @State private var launchAtLoginStatus = LaunchAtLoginController.status
    @State private var launchAtLoginError: String?

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginStatus.isEnabled },
            set: updateLaunchAtLogin
        )
    }

    private var saveButtonUsesFolderBinding: Binding<Bool> {
        Binding(
            get: { _ = saveButtonUsesFolder; return UpshotPreferences.saveButtonUsesConfiguredFolder },
            set: { saveButtonUsesFolder = $0 }
        )
    }

    @Environment(SettingsPermissions.self) private var permissions

    var body: some View {
        SettingsPage {
            Section("Permissions") {
                ForEach(SettingsPermissions.Kind.allCases) { kind in
                    SettingsPermissionRow(kind: kind, permissions: permissions)
                }
            }

            Section("Save Location") {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondaryLabel)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export folder")
                        Text(UpshotPreferences.exportDirectory.abbreviatedPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(UpshotPreferences.exportDirectory.path)
                    }

                    Spacer(minLength: 8)

                    if !exportDirectoryPath.isEmpty {
                        InspectorResetButton(help: "Use the default folder") {
                            exportDirectoryPath = ""
                        }
                        .transition(.blurPop)
                    }

                    SettingsButton("Change…") {
                        chooseExportDirectory()
                    }
                }
                .motion(value: exportDirectoryPath.isEmpty)

                Toggle(isOn: saveButtonUsesFolderBinding) {
                    SettingsControlLabel(
                        "Save without choosing a location",
                        detail: "When you click Save, write straight to the export folder instead of asking where to put it."
                    )
                }
                .toggleStyle(.ink)
            }

            Section("Library") {
                Toggle(isOn: $analyzeCaptures) {
                    SettingsControlLabel(
                        "Analyze captures",
                        detail: "Read the text in screenshots and recordings so search can find it, and sort new captures into categories. Everything runs on this Mac."
                    )
                }
                .toggleStyle(.ink)

                if analyzeCaptures, CaptureLibraryAnalyzer.isModelAvailable {
                    Toggle(isOn: $sortExistingCaptures) {
                        SettingsControlLabel(
                            "Sort existing captures",
                            detail: "Use Apple Intelligence on captures taken before sorting was turned on. It works in the background and can take an hour or more for a large Library."
                        )
                    }
                    .toggleStyle(.ink)
                    .transition(.blurPop)
                }
            }
            .motion(value: analyzeCaptures)
            .onChange(of: analyzeCaptures) { _, _ in CaptureLibraryIndex.shared.settingsDidChange() }
            .onChange(of: sortExistingCaptures) { _, _ in CaptureLibraryIndex.shared.settingsDidChange() }

            Section("System") {
                Toggle(isOn: launchAtLoginBinding) {
                    SettingsControlLabel(
                        "Launch at login",
                        detail: "Start Upshot automatically when you sign in."
                    )
                }
                .toggleStyle(.ink)

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(Palette.record)
                } else if launchAtLoginStatus.requiresApproval {
                    Text("Approve Upshot in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $playSounds) {
                    SettingsControlLabel(
                        "Play sounds",
                        detail: "Play the camera shutter sound when a screenshot is taken."
                    )
                }
                .toggleStyle(.ink)

                Toggle(isOn: $showMenuBarIcon) {
                    SettingsControlLabel(
                        "Show menu bar icon",
                        detail: "When hidden, reopen Upshot to get back to Settings."
                    )
                }
                .toggleStyle(.ink)

                Toggle(isOn: $hideDockIcon) {
                    SettingsControlLabel(
                        "Hide Dock icon",
                        detail: "Keep Upshot out of the Dock and Cmd-Tab, even while its windows are open. The menu bar won't show Upshot's menus."
                    )
                }
                .toggleStyle(.ink)
            }

            Section("Capture Visibility") {
                Toggle(isOn: $includeAppWindowsInCaptures) {
                    SettingsControlLabel(
                        "Include Upshot windows in captures",
                        detail: "Show preview cards, recording controls, Settings, and other Upshot windows in screenshots and screen recordings."
                    )
                }
                .toggleStyle(.ink)
            }
        }
        .onAppear {
            refreshLaunchAtLoginStatus()
        }
        .onChange(of: hideDockIcon) { _, _ in
            AppActivationPolicy.dockIconPreferenceDidChange()
        }
        .onChange(of: includeAppWindowsInCaptures) { _, _ in
            PreviewWindowCaptureExclusion.shared.refreshRegisteredWindows()
        }
    }

    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Save Location"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = UpshotPreferences.exportDirectory

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        exportDirectoryPath = url.path
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LaunchAtLoginController.status
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        do {
            launchAtLoginError = nil
            try LaunchAtLoginController.setEnabled(isEnabled)
        } catch {
            launchAtLoginError = "Could not update Launch at Login: \(error.localizedDescription)"
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
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .disabled
        @unknown default:
            .disabled
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
