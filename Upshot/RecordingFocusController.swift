import Foundation
import Darwin

@MainActor
final class RecordingFocusController {
    static let shared = RecordingFocusController()

    private struct Restoration: Codable, Sendable {
        let shortcutName: String
        let previousFocus: String
    }

    private var startTask: Task<String?, Never>?
    private var restoration: Restoration?

    private var restorationURL: URL {
        RecordingSessionStore.recordingsDirectory.deletingLastPathComponent()
            .appendingPathComponent("recording-focus-restoration.json")
    }

    private init() {}

    func begin() async -> String? {
        guard UpshotPreferences.recordingDoNotDisturb else { return nil }
        let task = Task { await prepareAndEnable() }
        startTask = task
        let warning = await task.value
        startTask = nil
        return warning
    }

    func restore() async -> String? {
        if let startTask {
            _ = await startTask.value
        }
        return await restorePendingFocus()
    }

    private func prepareAndEnable() async -> String? {
        if let warning = await restorePendingFocus() { return warning }
        let name = UpshotPreferences.recordingFocusShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return "Do Not Disturb was not enabled. Configure the recording Focus shortcut in Settings."
        }
        do {
            let previousFocus = try await RecordingFocusShortcut.run(name: name, action: "snapshot", previousFocus: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !previousFocus.isEmpty else {
                throw RecordingFocusShortcut.Failure(message: "The Focus shortcut returned no saved Focus state.")
            }
            let restoration = Restoration(shortcutName: name, previousFocus: previousFocus)
            let data = try JSONEncoder().encode(restoration)
            try FileManager.default.createDirectory(at: restorationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: restorationURL, options: .atomic)
            self.restoration = restoration
            _ = try await RecordingFocusShortcut.run(name: name, action: "enable", previousFocus: previousFocus)
            NSLog("[Upshot] Recording Do Not Disturb enabled; previous Focus saved")
            return nil
        } catch {
            NSLog("[Upshot] Recording Do Not Disturb failed: \(error.localizedDescription)")
            let restoreWarning = await restorePendingFocus()
            return ["Do Not Disturb could not be enabled: \(error.localizedDescription)", restoreWarning]
                .compactMap { $0 }.joined(separator: "\n\n")
        }
    }

    private func restorePendingFocus() async -> String? {
        do {
            if restoration == nil, FileManager.default.fileExists(atPath: restorationURL.path) {
                restoration = try JSONDecoder().decode(Restoration.self, from: Data(contentsOf: restorationURL))
            }
            guard let restoration else { return nil }
            _ = try await RecordingFocusShortcut.run(
                name: restoration.shortcutName,
                action: "restore",
                previousFocus: restoration.previousFocus
            )
            try FileManager.default.removeItem(at: restorationURL)
            self.restoration = nil
            NSLog("[Upshot] Recording Do Not Disturb restored previous Focus")
            return nil
        } catch {
            NSLog("[Upshot] Recording Do Not Disturb restoration failed: \(error.localizedDescription)")
            return "The previous Focus could not be restored: \(error.localizedDescription). The saved Focus state will be retried before the next recording."
        }
    }
}

nonisolated private enum RecordingFocusShortcut {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Request: Encodable {
        let action: String
        let previousFocus: String
    }

    static func run(name: String, action: String, previousFocus: String) async throws -> String {
        let directory = RecordingSessionStore.recordingsDirectory.deletingLastPathComponent()
            .appendingPathComponent("Focus Requests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("request.json")
        let output = directory.appendingPathComponent("response.txt")
        let diagnostic = directory.appendingPathComponent("diagnostic.txt")
        try JSONEncoder().encode(Request(action: action, previousFocus: previousFocus)).write(to: input, options: .atomic)
        FileManager.default.createFile(atPath: diagnostic.path, contents: nil)
        let diagnosticHandle = try FileHandle(forWritingTo: diagnostic)
        defer { try? diagnosticHandle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name, "--input-path", input.path, "--output-path", output.path, "--output-type", "public.plain-text"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = diagnosticHandle
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            let message = (try? String(contentsOf: diagnostic, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: message?.isEmpty == false ? message! : "The Focus shortcut failed or exceeded 30 seconds.")
        }
        return (try? String(contentsOf: output, encoding: .utf8)) ?? ""
    }
}
