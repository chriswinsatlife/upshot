//
//  SettingsAboutPane.swift
//  Upshot
//

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

    var body: some View {
        InterfaceFormPage {
            Section {
                VStack(spacing: Space.l) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

                    VStack(spacing: Space.s) {
                        Text("Upshot")
                            .font(.dsDisplay)
                        Tag(text: versionText)
                    }

                    Text("Screenshots and screen recordings, made beautiful in a click.")
                        .font(.dsCallout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    GlassEffectContainer(spacing: GlassMetrics.containerSpacing) {
                        HStack(spacing: GlassMetrics.gap) {
                            InterfaceActionButton("Check for Updates", systemImage: "arrow.down.circle") {
                                updaterManager.checkForUpdates()
                            }
                            .disabled(!updaterManager.canCheckForUpdates)
                        }
                    }
                    .padding(.top, Space.xs)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xxl)
            }

            Section("Updates") {
                Toggle(isOn: Binding(
                    get: { updaterManager.automaticallyChecksForUpdates },
                    set: { updaterManager.automaticallyChecksForUpdates = $0 }
                )) {
                    InterfaceRowLabel(
                        "Check for updates automatically",
                        detail: "Upshot looks for a new version in the background and asks before installing it."
                    )
                }
                .toggleStyle(.ink)
            }
        }
    }
}
