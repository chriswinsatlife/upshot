import Foundation

extension UpshotPreferences {
    static var recordingExtendedExportDefaults: RecordingExportDeliveryOptions {
        get {
            guard let data = UserDefaults.standard.data(forKey: "recordingExtendedExportDefaults"),
                  let options = try? JSONDecoder().decode(RecordingExportDeliveryOptions.self, from: data) else {
                return RecordingExportDeliveryOptions()
            }
            return options
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: "recordingExtendedExportDefaults")
        }
    }
}

nonisolated enum RecordingExportFormat: String, Codable, CaseIterable, Sendable {
    case video = "Video"
    case gif = "GIF"
}

nonisolated enum RecordingGIFFrameRate: Int, Codable, CaseIterable, Sendable {
    case fps10 = 10
    case fps15 = 15
    case fps20 = 20
    case fps25 = 25
    case fps30 = 30
}

nonisolated enum RecordingGIFQuality: String, Codable, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var colorLevels: Float {
        switch self {
        case .low: 4
        case .medium: 6
        case .high: 8
        }
    }
}

nonisolated struct RecordingExportDeliveryOptions: Codable, Equatable, Sendable {
    var format: RecordingExportFormat = .video
    var gifFrameRate: RecordingGIFFrameRate = .fps15
    var gifQuality: RecordingGIFQuality = .high
    var optimizesGIF = true
    var scalesRetinaToOne = false
    var monoAudio = false
    var separateAudioTracks = false
}

nonisolated enum RecordingExportOptionStore {
    static func url(for recording: URL) -> URL {
        recording.appendingPathComponent("export-options.json")
    }

    static func load(from recording: URL) -> RecordingExportDeliveryOptions? {
        guard let data = try? Data(contentsOf: url(for: recording)) else { return nil }
        return try? JSONDecoder().decode(RecordingExportDeliveryOptions.self, from: data)
    }

    static func save(_ options: RecordingExportDeliveryOptions, to recording: URL) throws {
        try JSONEncoder().encode(options).write(to: url(for: recording), options: .atomic)
    }
}
