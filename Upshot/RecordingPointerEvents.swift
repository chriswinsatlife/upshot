import CoreGraphics
import Foundation

nonisolated struct PointerCaptureFile: Codable, Sendable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion = Self.currentFormatVersion
    var travel: [PointerTravelSample] = []
    var presses: [PointerPressEvent] = []
    var keystrokes: [RecordingKeystrokeEvent] = []
    var artwork: [PointerArtwork] = []

    var isSanitized = false
}

nonisolated struct RecordingKeystrokeEvent: Codable, Sendable, Equatable {

    var time: TimeInterval

    var modifiers: [String] = []

    var key: String
}

nonisolated struct PointerTravelSample: Codable, Sendable, Equatable {
    nonisolated enum PointerTravelKind: String, Codable, Sendable {
        case move
        case drag
    }

    var time: TimeInterval
    var x: Double
    var y: Double
    var kind: PointerTravelKind = .move

    var artworkID: String? = nil
}

nonisolated struct PointerPressEvent: Codable, Sendable, Equatable {
    nonisolated enum PressPhase: String, Codable, Sendable {
        case down
        case up
    }

    var time: TimeInterval
    var x: Double
    var y: Double
    var button: Int
    var phase: PressPhase

    var artworkID: String? = nil
}

nonisolated struct PointerArtwork: Codable, Sendable, Equatable {
    nonisolated struct Point: Codable, Sendable, Equatable {
        var x: Double
        var y: Double
    }

    nonisolated struct Size: Codable, Sendable, Equatable {
        var width: Double
        var height: Double
    }

    var artworkID: String
    var imageData: Data

    var anchorPoint: Point
    var referenceSize: Size

    var leans = false

    private enum CodingKeys: String, CodingKey {
        case artworkID, imageData, anchorPoint, referenceSize
    }
}

nonisolated extension PointerCaptureFile {
    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case travel
        case presses
        case keystrokes
        case artwork
        case isSanitized
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        travel = try container.decodeIfPresent([PointerTravelSample].self, forKey: .travel) ?? []
        presses = try container.decodeIfPresent([PointerPressEvent].self, forKey: .presses) ?? []
        keystrokes = try container.decodeIfPresent(
            [RecordingKeystrokeEvent].self,
            forKey: .keystrokes
        ) ?? []
        artwork = try container.decodeIfPresent(
            [PointerArtwork].self,
            forKey: .artwork
        ) ?? []
        isSanitized = try container.decodeIfPresent(Bool.self, forKey: .isSanitized) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(travel, forKey: .travel)
        try container.encode(presses, forKey: .presses)
        try container.encode(keystrokes, forKey: .keystrokes)
        try container.encode(artwork, forKey: .artwork)
        try container.encode(isSanitized, forKey: .isSanitized)
    }
}

nonisolated extension PointerTravelSample {
    private enum CodingKeys: String, CodingKey {
        case time
        case x
        case y
        case kind
        case artworkID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(TimeInterval.self, forKey: .time)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        kind = try container.decodeIfPresent(
            PointerTravelKind.self,
            forKey: .kind
        ) ?? .move
        artworkID = try container.decodeIfPresent(String.self, forKey: .artworkID)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time, forKey: .time)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(artworkID, forKey: .artworkID)
    }
}
