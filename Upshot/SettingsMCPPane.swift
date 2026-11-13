import AppKit
import SwiftUI

struct MCPSettingsPane: View {
    @AppStorage(UpshotPreferences.agentServerEnabledKey) private var agentServerEnabled = true
    @State private var copiedSetup: Setup? = UpshotStorage.isRenderingStates && StateRenderer.scenario.contains("copied") ? .claudeCode : nil
    @State private var serverIsRunning = MCPSettingsPane.currentServerIsRunning

    private enum Setup: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case codex = "Codex"
        case json = "Other MCP clients"

        var id: Self { self }
    }

    private static let commandFieldMaximumWidth: CGFloat = 400

    private static var currentServerIsRunning: Bool {
        if UpshotStorage.isRenderingStates {
            return !StateRenderer.scenario.contains("failed")
        }
        return AgentServer.shared.isRunning
    }

    private var executablePath: String {
        Bundle.main.executableURL?.path ?? "/Applications/Upshot.app/Contents/MacOS/Upshot"
    }

    private func command(for setup: Setup) -> String {
        let quoted = "'\(executablePath.replacingOccurrences(of: "'", with: "'\\''"))'"
        switch setup {
        case .claudeCode:
            return "claude mcp add upshot -- \(quoted) \(AgentSocket.relayArgument)"
        case .codex:
            return "codex mcp add upshot -- \(quoted) \(AgentSocket.relayArgument)"
        case .json:
            let config: JSONValue = [
                "mcpServers": [
                    "upshot": [
                        "command": .string(executablePath),
                        "args": [.string(AgentSocket.relayArgument)],
                    ],
                ],
            ]
            return config.compactString
        }
    }

    var body: some View {
        InterfaceFormPage {
            InterfaceSection("AI Agents") {
                InterfaceToggleRow(
                    "Allow AI agents",
                    detail: "Agents can read, edit, and export recordings on this Mac.",
                    isOn: $agentServerEnabled
                )
                .onChange(of: agentServerEnabled) { _, _ in
                    AgentServer.shared.updateForPreference()
                    serverIsRunning = Self.currentServerIsRunning
                }
                if agentServerEnabled {
                    InterfaceRow("Server") {
                        serverStatus
                    }
                    .transition(.blurPop)
                }
            }

            if agentServerEnabled {
                InterfaceSection(
                    "Connect an Agent",
                    footer: "Agents start Upshot in the background when they need it."
                ) {
                    ForEach(Setup.allCases) { setup in
                        InterfaceRow(setup.rawValue) {
                            HStack(spacing: Space.m) {
                                commandField(for: setup)
                                copyButton(for: setup)
                            }
                        }
                    }
                }
                .transition(.blurPop)
            }
        }
        .motion(value: agentServerEnabled)
        .onAppear { serverIsRunning = Self.currentServerIsRunning }
    }

    private var serverStatus: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: serverIsRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(serverIsRunning ? Palette.success : Palette.destructiveLabel)
            Text(serverIsRunning ? "Running" : "Could not start")
                .foregroundStyle(serverIsRunning ? Palette.secondaryLabel : Palette.destructiveLabel)
        }
        .font(.dsBody)
        .accessibilityElement(children: .combine)
    }

    private func commandField(for setup: Setup) -> some View {
        let command = command(for: setup)
        return Text(command)
            .font(.dsCaption.monospaced())
            .foregroundStyle(Palette.secondaryLabel)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: Self.commandFieldMaximumWidth, alignment: .leading)
            .interfaceFieldChrome()
            .help(command)
            .layoutPriority(1)
    }

    private func copyButton(for setup: Setup) -> some View {
        let isCopied = copiedSetup == setup
        return Button {
            copy(setup)
        } label: {
            ZStack {
                Label("Copied", systemImage: "checkmark").hidden()
                Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
            }
        }
        .accessibilityLabel(isCopied ? "Copied \(setup.rawValue) setup" : "Copy \(setup.rawValue) setup")
    }

    private func copy(_ setup: Setup) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command(for: setup), forType: .string)
        copiedSetup = setup
        AppLog.event("automation", "agent_setup_copied", fields: ["client": setup.rawValue])
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedSetup == setup { copiedSetup = nil }
        }
    }
}
