import Foundation

nonisolated struct RecordingExportAppearance: Codable, Equatable, Sendable {
    var zoomAnimationStyle: RecordingZoomAnimationStyle = .smooth
    var zoomMotion: RecordingZoomMotionSettings? = RecordingZoomMotionSettings()
    var keystrokes = RecordingKeystrokeAppearance()
    var shot: RecordingExportShot = .flat

    init() {}

    static var legacy: Self {
        var appearance = Self()
        appearance.zoomMotion = nil
        return appearance
    }

    private enum CodingKeys: String, CodingKey {
        case zoomAnimationStyle, zoomMotion, keystrokes, shot
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        zoomAnimationStyle = try values.decodeIfPresent(RecordingZoomAnimationStyle.self, forKey: .zoomAnimationStyle) ?? .smooth
        zoomMotion = try values.decodeIfPresent(RecordingZoomMotionSettings.self, forKey: .zoomMotion)
        keystrokes = try values.decodeIfPresent(RecordingKeystrokeAppearance.self, forKey: .keystrokes) ?? RecordingKeystrokeAppearance()
        shot = try values.decodeIfPresent(RecordingExportShot.self, forKey: .shot) ?? .flat
    }
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
