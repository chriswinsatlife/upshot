import Foundation
import Observation

@MainActor
@Observable
final class RecordingStudioFinalization {
    static let shared = RecordingStudioFinalization()

    enum State: Equatable {
        case finishing
        case ready(URL)
        case failed(String)
    }

    private var states: [URL: State] = [:]

    private init() {}

    func state(for url: URL?) -> State? {
        guard let url else { return nil }
        return states[url.standardizedFileURL]
    }

    func begin(_ session: RecordingSession) {
        states[session.directoryURL.standardizedFileURL] = .finishing
        AppLog.event("recording", "recording_editor_finalization_started")
    }

    func complete(_ session: RecordingSession, editorURL: URL) {
        let key = session.directoryURL.standardizedFileURL
        guard states[key] != nil else { return }
        states[key] = .ready(editorURL)
        AppLog.event("recording", "recording_editor_finalization_completed")
    }

    func fail(_ session: RecordingSession, message: String) {
        let key = session.directoryURL.standardizedFileURL
        guard states[key] != nil else { return }
        states[key] = .failed(message)
        AppLog.event("recording", "recording_editor_finalization_failed")
    }
}
