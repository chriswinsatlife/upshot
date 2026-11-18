import CoreGraphics
import Foundation

extension UpshotPreferences {
    static var recordingExtendedExportDefaults: RecordingExportDeliveryOptions {
        get {
            guard let data = UpshotStorage.defaults.data(forKey: "recordingExtendedExportDefaults"),
                  let options = try? JSONDecoder().decode(RecordingExportDeliveryOptions.self, from: data) else {
                return RecordingExportDeliveryOptions()
            }
            return options
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UpshotStorage.defaults.set(data, forKey: "recordingExtendedExportDefaults")
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

nonisolated enum RecordingGIFSize: String, Codable, CaseIterable, Sendable {
    case p720 = "Up to 720p"
    case p1080 = "Up to 1080p"
    case original = "Original"

    func outputSize(for source: CGSize) -> CGSize {
        guard source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0 else {
            return CGSize(width: 1280, height: 720)
        }
        let heightLimit: CGFloat = switch self {
        case .p720: 720
        case .p1080: 1080
        case .original: 8192
        }
        let scale = min(1, heightLimit / source.height, 8192 / max(source.width, source.height))
        guard scale < 1 else { return source }
        return CGSize(
            width: min(8192, max(2, (Int((source.width * scale).rounded()) + 1) & ~1)),
            height: min(8192, max(2, (Int((source.height * scale).rounded()) + 1) & ~1))
        )
    }
}

nonisolated enum RecordingMotionBlurLevel: String, Codable, CaseIterable, Sendable {
    case off = "Off"
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var shutterFraction: Double {
        switch self {
        case .off: 0
        case .low: 0.25
        case .medium: 0.5
        case .high: 1
        }
    }
}

nonisolated struct RecordingExportDeliveryOptions: Codable, Equatable, Sendable {
    var format: RecordingExportFormat = .video
    var gifFrameRate: RecordingGIFFrameRate = .fps15
    var gifQuality: RecordingGIFQuality = .high
    var gifSize: RecordingGIFSize? = .p720
    var gifLoops: Bool?
    var optimizesGIF = true
    var scalesRetinaToOne = false
    var monoAudio = false
    var separateAudioTracks = false
    var motionBlurLevel: RecordingMotionBlurLevel?

    var effectiveGIFLoops: Bool { gifLoops ?? true }
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

extension UpshotPreferences {
    static var recordingCapturesTypedKeys: Bool {
        get { UpshotStorage.defaults.bool(forKey: "recordingCapturesTypedKeys") }
        set { UpshotStorage.defaults.set(newValue, forKey: "recordingCapturesTypedKeys") }
    }
}
