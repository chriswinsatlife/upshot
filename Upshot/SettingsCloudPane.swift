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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedCredentialField: CredentialField?

    private static let versionManifestURL = "https://raw.githubusercontent.com/fayazara/screendrop-worker/main/version.json"
    private static let workerRepositoryURL = "https://github.com/fayazara/screendrop-worker"
    private static let deployToCloudflareURL = "https://deploy.workers.cloudflare.com/?url=https://github.com/fayazara/screendrop-worker"

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
            InterfaceSection("Cloudflare Worker") {
                uploadTokenRow

                InterfaceRow("Worker") {
                    Button("View on GitHub") {
                        Self.open(Self.workerRepositoryURL)
                    }
                    Button("Deploy to Cloudflare") {
                        Self.open(Self.deployToCloudflareURL)
                    }
                }

                workerURLRow

                if isWorkerOutdated, let deployed = deployedWorkerVersion, let latest = latestWorkerVersion {
                    InterfaceRow("Worker update available", detail: "v\(deployed) → v\(latest)") {
                        Button("How to Update") {
                            Self.open(updateGuideURL)
                        }
                    }
                }
            }

            InterfaceSection(nil) {
                DisclosureGroup(isExpanded: $setupGuideExpanded.animation(reduceMotion ? nil : .fold)) {
                    InterfaceRow("1. Copy the upload token") {}
                    InterfaceRow(
                        "2. Click Deploy to Cloudflare",
                        detail: "Cloudflare clones the worker, creates its R2 and D1 storage, and asks for the UPLOAD_TOKEN secret. Paste the upload token there."
                    ) {}
                    InterfaceRow("3. Paste the worker URL and click Verify") {}
                    SetupVideoPlayer()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
                        .padding(.vertical, Space.xs)
                } label: {
                    InterfaceRowLabel("Setup Guide")
                }
            }
        }
        .onAppear {
            loadFromStore()
            Task { focusedCredentialField = nil }
        }
        .task {
            guard !UpshotStorage.isRenderingStates else { return }
            if isWorkerConfigured {
                await testWorkerConnection()
            }
        }
    }

    private var uploadTokenRow: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            InterfaceRow("Upload Token") {
                Button(tokenRevealed ? "Hide" : "Show") {
                    tokenRevealed.toggle()
                }
                .disabled(uploadToken.isEmpty)
                .help(tokenRevealed ? "Hide token" : "Reveal token")

                Button(tokenCopied ? "Copied" : "Copy") {
                    copyToken()
                }
                .disabled(uploadToken.isEmpty)
                .motion(.morphQuick, value: tokenCopied)

                Button("Regenerate") {
                    regenerateToken()
                }
            }

            Group {
                if tokenRevealed {
                    TextField("", text: $uploadToken, prompt: Text("Paste your token"))
                } else {
                    SecureField("", text: $uploadToken, prompt: Text("Paste your token"))
                }
            }
            .labelsHidden()
            .font(.dsBody)
            .lineLimit(1)
            .interfaceFieldChrome()
            .focused($focusedCredentialField, equals: .uploadToken)
            .accessibilityLabel("Upload Token")
            .onChange(of: uploadToken) { fieldDidChange() }
        }
        .padding(.bottom, Space.xs)
    }

    private var workerURLRow: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            InterfaceRow("Worker URL", detail: connectionFailureMessage, detailIsCritical: true) {
                connectionStatusLabel
                    .motion(.morphQuick, value: workerStatus)
                Button("Verify") {
                    Task { await testWorkerConnection() }
                }
                .disabled(!isWorkerConfigured)
            }

            TextField("", text: $workerURL, prompt: Text("https://…workers.dev"))
                .labelsHidden()
                .font(.dsBody)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                .interfaceFieldChrome()
                .focused($focusedCredentialField, equals: .workerURL)
                .accessibilityLabel("Worker URL")
                .onChange(of: workerURL) { _, newValue in
                    let cleaned = newValue.components(separatedBy: .whitespacesAndNewlines).joined()
                    if cleaned != newValue {
                        workerURL = cleaned
                    }
                    fieldDidChange()
                }
        }
        .padding(.bottom, Space.xs)
    }

    private var connectionFailureMessage: String? {
        if case .failed(let message) = workerStatus {
            return message
        }
        return nil
    }

    @ViewBuilder
    private var connectionStatusLabel: some View {
        if !isWorkerConfigured {
            Text("Not configured")
                .font(.dsBody)
                .foregroundStyle(Palette.secondaryLabel)
        } else {
            switch workerStatus {
            case .unchecked:
                Text("Not verified")
                    .font(.dsBody)
                    .foregroundStyle(Palette.secondaryLabel)
            case .checking:
                HStack(spacing: Space.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking…")
                        .font(.dsBody)
                        .foregroundStyle(Palette.secondaryLabel)
                }
            case .connected:
                HStack(spacing: Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: IconSize.row))
                        .foregroundStyle(Palette.success)
                    Text("Connected")
                        .font(.dsBody)
                        .foregroundStyle(Palette.label)
                }
            case .failed:
                HStack(spacing: Space.xs) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: IconSize.row))
                    Text("Failed")
                        .font(.dsBody)
                }
                .foregroundStyle(Palette.destructiveLabel)
            }
        }
    }

    private static func open(_ address: String) {
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadFromStore() {
        if UpshotStorage.isRenderingStates {
            workerURL = StateRenderer.scenario.contains("configured") || StateRenderer.scenario.contains("connected") || StateRenderer.scenario.contains("failed") ? "https://uploads.example.com" : ""
            uploadToken = String(repeating: "0", count: 64)
            setupGuideExpanded = workerURL.isEmpty
            workerStatus = StateRenderer.scenario.contains("connected") ? .connected : StateRenderer.scenario.contains("failed") ? .failed("Could not connect to the worker.") : .unchecked
            if StateRenderer.scenario.contains("update") {
                deployedWorkerVersion = "1.2.0"
                latestWorkerVersion = "1.3.0"
            }
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

private enum CredentialField: Hashable {
    case uploadToken
    case workerURL
}
