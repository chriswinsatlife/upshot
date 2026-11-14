import Foundation

nonisolated struct RecordingExportAppearance: Codable, Equatable, Sendable {
    var zoomAnimationStyle: RecordingZoomAnimationStyle = .smooth
    var keystrokes = RecordingKeystrokeAppearance()
    var shot: RecordingExportShot = .flat
}

nonisolated enum RecordingExportAppearanceStore {
    static func load(from recording: URL) -> RecordingExportAppearance? {
        guard let data = try? Data(contentsOf: recording.appendingPathComponent("export-appearance.json")) else { return nil }
        return try? JSONDecoder().decode(RecordingExportAppearance.self, from: data)
    }

    static func save(_ appearance: RecordingExportAppearance, to recording: URL) throws {
        let url = recording.appendingPathComponent("export-appearance.json")
        try JSONEncoder().encode(appearance).write(to: url, options: .atomic)
    }
}
