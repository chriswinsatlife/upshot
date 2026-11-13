import AppKit
import SwiftUI

struct SettingsAboutPane: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?):
            return "Version \(version) (\(build))"
        case let (version?, nil):
            return "Version \(version)"
        default:
            return "Version 1.0"
        }
    }

    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding(
            get: { updaterManager.automaticallyChecksForUpdates },
            set: { updaterManager.automaticallyChecksForUpdates = $0 }
        )
    }

    var body: some View {
        InterfaceFormPage {
            Section {
                InterfaceToggleRow("Check for updates automatically", isOn: automaticallyChecksForUpdates)
            } header: {
                SettingsAboutIdentity(versionText: versionText) {
                    InterfaceActionButton("Check for Updates") {
                        updaterManager.checkForUpdates()
                    }
                    .disabled(!updaterManager.canCheckForUpdates)
                }
            }
        }
    }
}

private struct SettingsAboutIdentity<Action: View>: View {
    let versionText: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: Space.xl) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: Space.xs) {
                Text("Upshot")
                    .font(.dsDisplay)
                    .foregroundStyle(Palette.label)
                    .accessibilityAddTraits(.isHeader)
                Text(versionText)
                    .font(.dsBody)
                    .foregroundStyle(Palette.secondaryLabel)
                    .textSelection(.enabled)
            }

            action()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxxl)
        .padding(.bottom, Space.xxl)
        .textCase(nil)
    }
}
