import AppKit
import AVKit
import Security
import SwiftUI

struct CloudSettingsPane: View {
    @State private var store = CloudCredentialStore.shared

    @State private var workerURL = ""
    @State private var uploadToken = ""

    @State private var workerStatus: ConnectionStatus = .unchecked
    @State private var isLoading = true
    @State private var tokenRevealed = false
    @State private var tokenCopied = false
    @State private var setupGuideExpanded = true

    @State private var deployedWorkerVersion: String?
    @State private var latestWorkerVersion: String?
    @State private var updateGuideURL = "https://github.com/fayazara/screendrop-worker#updating-your-worker"

    private static let versionManifestURL = "https://raw.githubusercontent.com/fayazara/screendrop-worker/main/version.json"

    private var isWorkerOutdated: Bool {
        guard let deployed = deployedWorkerVersion, let latest = latestWorkerVersion else {
            return false
        }
        return Self.isVersion(deployed, olderThan: latest)
    }

    private var isWorkerConfigured: Bool {
        !workerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !uploadToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        InterfaceFormPage {

            Section {
                HStack(spacing: 12) {
                    Text("Worker URL")
                        .frame(width: 100, alignment: .leading)
                    TextField("Worker URL", text: $workerURL, prompt: Text("https://…workers.dev"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        .onChange(of: workerURL) { _, newValue in
                            let cleaned = newValue.components(separatedBy: .whitespacesAndNewlines).joined()
                            if cleaned != newValue {
                                workerURL = cleaned
                            }
                            fieldDidChange()
                        }
                }

                HStack(spacing: 12) {
                    Text("Upload Token")
                        .frame(width: 100, alignment: .leading)
                    Group {
                        if tokenRevealed {
                            TextField("Upload Token", text: $uploadToken, prompt: Text("Paste your token"))
                        } else {
                            SecureField("Upload Token", text: $uploadToken, prompt: Text("Paste your token"))
                        }
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .onChange(of: uploadToken) { fieldDidChange() }

                    Button {
                        tokenRevealed.toggle()
                    } label: {
                        Image(systemName: tokenRevealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(uploadToken.isEmpty)
                    .help(tokenRevealed ? "Hide token" : "Reveal token")
                }

                HStack(spacing: 8) {
                    InterfaceActionButton(
                        tokenCopied ? "Copied" : "Copy Token",
                        systemImage: tokenCopied ? "checkmark" : "doc.on.doc"
                    ) {
                        copyToken()
                    }
                    .disabled(uploadToken.isEmpty)
                    .motion(.morphQuick, value: tokenCopied)

                    InterfaceActionButton("Regenerate", systemImage: "arrow.triangle.2.circlepath") {
                        regenerateToken()
                    }

                    Spacer()

                    if case .checking = workerStatus {
                        connectionStatusIndicator(workerStatus)
                    }
                    InterfaceActionButton(
                        workerStatus == .connected ? "Connected" : "Verify Connection",
                        systemImage: workerStatus == .connected ? "checkmark.circle.fill" : "bolt.horizontal"
                    ) {
                        Task { await testWorkerConnection() }
                    }
                    .disabled(!isWorkerConfigured)
                    .motion(.morphQuick, value: workerStatus == .connected)
                }
            } header: {
                Text("Connection")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if case .failed(let message) = workerStatus {
                        Label(message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(Palette.record)
                            .font(.callout)
                    }
                    Text("Paste this token as the **UPLOAD_TOKEN** secret when you deploy the worker to Cloudflare.")
                }
            }

            if isWorkerOutdated {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Palette.warning)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Worker update available")
                                .font(.callout.weight(.medium))
                            if let deployed = deployedWorkerVersion, let latest = latestWorkerVersion {
                                Text("v\(deployed) → v\(latest)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        InterfaceActionButton("How to Update") {
                            if let url = URL(string: updateGuideURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section {
                GlassActionCapsule(
                    title: "Deploy to Cloudflare",
                    systemImage: "cloud.fill",
                    isProminent: true
                ) {
                    if let url = URL(string: "https://deploy.workers.cloudflare.com/?url=https://github.com/fayazara/screendrop-worker") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(.vertical, 2)

                Button {
                    withAnimation(.morphIfAllowed) {
                        setupGuideExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(setupGuideExpanded ? 90 : 0))
                        Text("Setup steps & demo")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if setupGuideExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        SetupStepView(
                            number: 1,
                            text: "Copy the upload token above - you'll paste it into Cloudflare in the next step."
                        )
                        SetupStepView(
                            number: 2,
                            text: "Click \"Deploy to Cloudflare\". It clones the worker, provisions R2 + D1, and asks for the UPLOAD_TOKEN secret - paste the token you copied."
                        )
                        SetupStepView(
                            number: 3,
                            text: "Paste your worker URL above, then click \"Verify Connection\" to finish setup and confirm."
                        )

                        SetupVideoPlayer()
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
                    }
                    .padding(.top, 4)
                }
            } header: {
                HStack {
                    Text("Setup Guide")
                    Spacer()
                    InterfaceActionButton("View on GitHub") {
                        if let url = URL(string: "https://github.com/fayazara/screendrop-worker") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(overallStatusColor)
                        .frame(width: 7, height: 7)

                    Text(overallStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            loadFromStore()
        }
        .task {
            guard !UpshotStorage.isRenderingStates else { return }
            if isWorkerConfigured {
                await testWorkerConnection()
            }
        }
    }

    private func loadFromStore() {
        if UpshotStorage.isRenderingStates {
            workerURL = StateRenderer.scenario.contains("configured") || StateRenderer.scenario.contains("connected") || StateRenderer.scenario.contains("failed") ? "https://uploads.example.com" : ""
            uploadToken = String(repeating: "0", count: 64)
            setupGuideExpanded = !StateRenderer.scenario.contains("configured")
            workerStatus = StateRenderer.scenario.contains("connected") ? .connected : StateRenderer.scenario.contains("failed") ? .failed("Could not connect to the worker.") : .unchecked
            isLoading = false
            return
        }
        isLoading = true
        workerURL = store.workerURL
        uploadToken = store.uploadToken

        setupGuideExpanded = workerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if uploadToken.isEmpty {
            let token = Self.generateToken()
            uploadToken = token
            store.uploadToken = token
        }

        DispatchQueue.main.async {
            isLoading = false
        }
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }

        return (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(uploadToken, forType: .string)
        tokenCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            tokenCopied = false
        }
    }

    private func regenerateToken() {
        let token = Self.generateToken()
        uploadToken = token
        store.uploadToken = token
        workerStatus = .unchecked
        copyToken()
    }

    private func fieldDidChange() {
        guard !UpshotStorage.isRenderingStates, !isLoading else { return }
        workerStatus = .unchecked
        deployedWorkerVersion = nil
        saveSettings()
    }

    private func saveSettings() {
        store.workerURL = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        store.uploadToken = uploadToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func testWorkerConnection() async {
        saveSettings()
        workerStatus = .checking

        let raw = workerURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = raw.lowercased().hasPrefix("http") ? raw : "https://\(raw)"
        let token = uploadToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let setupURL = URL(string: "\(base)/api/setup"),
              let pingURL = URL(string: "\(base)/api/ping") else {
            workerStatus = .failed("Invalid URL")
            return
        }

        do {
            var request = URLRequest(url: setupURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200, 404:
                    break
                case 401, 403:
                    workerStatus = .failed("Invalid token")
                    return
                default:
                    workerStatus = .failed("Setup failed (HTTP \(http.statusCode))")
                    return
                }
            }
        } catch {
            workerStatus = .failed(error.localizedDescription)
            return
        }

        var request = URLRequest(url: pingURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                workerStatus = .failed("No response")
                return
            }

            switch http.statusCode {
            case 200:
                workerStatus = .connected
                deployedWorkerVersion = Self.decodeVersion(from: data)
                await fetchLatestWorkerInfo()
            case 401, 403:
                workerStatus = .failed("Invalid token")
            default:
                workerStatus = .failed("HTTP \(http.statusCode)")
            }
        } catch {
            workerStatus = .failed(error.localizedDescription)
        }
    }

    private func fetchLatestWorkerInfo() async {
        guard let url = URL(string: Self.versionManifestURL) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let manifest = try JSONDecoder().decode(WorkerVersionManifest.self, from: data)
            latestWorkerVersion = manifest.version
            if let guide = manifest.updateGuide, !guide.isEmpty {
                updateGuideURL = guide
            }
        } catch {

        }
    }

    private static func decodeVersion(from data: Data) -> String? {
        struct PingResponse: Decodable { let version: String? }
        return (try? JSONDecoder().decode(PingResponse.self, from: data))?.version
    }

    private static func isVersion(_ lhs: String, olderThan rhs: String) -> Bool {
        func components(_ value: String) -> [Int] {
            value
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }

        let a = components(lhs)
        let b = components(rhs)
        let count = max(a.count, b.count)
        for index in 0..<count {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private var overallStatusColor: Color {
        if isWorkerConfigured {
            if workerStatus == .connected {
                return Palette.success
            }
            return Palette.warning
        }
        return .gray
    }

    private var overallStatusText: String {
        if !isWorkerConfigured {
            return "Not configured"
        }
        if workerStatus == .connected {
            return "Connected"
        }
        return "Not verified"
    }

    @ViewBuilder
    private func connectionStatusIndicator(_ status: ConnectionStatus) -> some View {
        switch status {
        case .unchecked:
            EmptyView()
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
                .font(.system(size: 13))
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.record)
                    .font(.system(size: 13))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.record)
                    .lineLimit(1)
            }
        }
    }
}

private enum ConnectionStatus: Equatable {
    case unchecked
    case checking
    case connected
    case failed(String)
}

private struct WorkerVersionManifest: Decodable {
    let version: String
    let updateGuide: String?
}

private struct SetupStepView: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.label)
                .frame(width: 22, height: 22)
                .glassEffect(.regular, in: .circle)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }
}

private struct SetupVideoPlayer: NSViewRepresentable {
    private static let videoURL = URL(string: "https://static.fayazahmed.com/8130A265-enable-cloud-screendrop.mp4")!

    func makeNSView(context: Context) -> AVPlayerView {
        let source = UpshotStorage.isRenderingStates ? StateRenderer.fixtureVideoURL : Self.videoURL
        let player = source.map { AVPlayer(url: $0) } ?? AVPlayer()
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = true
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
