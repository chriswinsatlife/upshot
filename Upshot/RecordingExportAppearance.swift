import Foundation

nonisolated enum RecordingZoomAnimationStyle: String, Codable, CaseIterable, Sendable {
    case smooth = "Smooth"
    case dynamic = "Dynamic"

    var spring: SpringConstant {
        switch self {
        case .smooth: SpringConstant(tension: 125, friction: 12, inertia: 1.5, clampsOvershoot: true)
        case .dynamic: SpringConstant(tension: 220, friction: 20, inertia: 1, clampsOvershoot: false)
        }
    }
}

nonisolated struct RecordingExportAppearance: Codable, Equatable, Sendable {
    var zoomAnimationStyle: RecordingZoomAnimationStyle = .smooth
    var keystrokes = RecordingKeystrokeAppearance()
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
