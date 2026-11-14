import CoreGraphics
import Foundation

nonisolated struct RecordingSession: Sendable, Equatable {
    static let directoryExtension = "upshotrec"
    static let screenFileName = "screen.mov"
    static let cameraFileName = "camera.mov"

    static let cameraMatteFileName = "camera-matte-v1.mov"
    static let pointerCaptureFileName = "input.json"
    static let captureManifestFileName = "capture.json"
    static let editDocumentFileName = "edit.json"

    static let draftDocumentFileName = "edit.draft.json"
    static let projectMetadataFileName = "project.json"

    static let renderStampFileName = "render.json"
    static let posterFileName = "poster.jpg"

    static let replacementAudioBaseName = "audio-replacement"

    let directoryURL: URL

    var screenURL: URL { directoryURL.appendingPathComponent(Self.screenFileName) }
    var cameraURL: URL { directoryURL.appendingPathComponent(Self.cameraFileName) }

    var finalURL: URL {
        finalURL(for: .default)
    }

    func finalURL(for container: VideoExportContainer) -> URL {
        let fileName = directoryURL
            .deletingPathExtension()
            .lastPathComponent
            .appending(".\(container.fileExtension)")
        return directoryURL.appendingPathComponent(fileName)
    }
    var pointerCaptureURL: URL { directoryURL.appendingPathComponent(Self.pointerCaptureFileName) }
    var captureManifestURL: URL { directoryURL.appendingPathComponent(Self.captureManifestFileName) }
    var editDocumentURL: URL { directoryURL.appendingPathComponent(Self.editDocumentFileName) }
    var draftDocumentURL: URL { directoryURL.appendingPathComponent(Self.draftDocumentFileName) }
    var projectMetadataURL: URL { directoryURL.appendingPathComponent(Self.projectMetadataFileName) }
    var renderStampURL: URL { directoryURL.appendingPathComponent(Self.renderStampFileName) }
    var posterURL: URL { directoryURL.appendingPathComponent(Self.posterFileName) }

    var hasSavedProject: Bool {
        FileManager.default.fileExists(atPath: editDocumentURL.path)
    }

    var displayName: String {
        let stored = loadProjectMetadata()?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return directoryURL.deletingPathExtension().lastPathComponent
    }

    var hasCamera: Bool {
        FileManager.default.fileExists(atPath: cameraURL.path)
    }

    var existingFinalURL: URL? {
        for container in VideoExportContainer.allCases {
            let candidate = finalURL(for: container)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    var hasFinalVideo: Bool {
        existingFinalURL != nil
    }

    var deliverableURL: URL {
        existingFinalURL ?? screenURL
    }

    func removeFinalVideos() {
        for container in VideoExportContainer.allCases {
            try? FileManager.default.removeItem(at: finalURL(for: container))
        }
        try? FileManager.default.removeItem(at: renderStampURL)
    }

    @discardableResult
    func installFinalVideo(
        movingFrom temporaryURL: URL,
        renderedFrom document: RecordingEditDocument? = nil
    ) throws -> URL {
        let container = VideoExportContainer(fileExtension: temporaryURL.pathExtension) ?? .default
        let destinationURL = finalURL(for: container)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }

        for stale in VideoExportContainer.allCases where stale != container {
            try? FileManager.default.removeItem(at: finalURL(for: stale))
        }
        writeRenderStamp(document)
        return destinationURL
    }

    static func differsOnlyByExportContainer(
        _ document: RecordingEditDocument,
        _ other: RecordingEditDocument?
    ) -> Bool {
        guard let other else { return false }
        var normalized = document
        normalized.exportSettings?.container = other.exportSettings?.container
        return normalized == other
    }

    static func isSessionDirectory(_ url: URL) -> Bool {
        url.pathExtension == directoryExtension
            && FileManager.default.fileExists(atPath: url.appendingPathComponent(screenFileName).path)
    }

    func loadCaptureManifest() -> CaptureManifest? {
        guard let data = try? Data(contentsOf: captureManifestURL) else { return nil }
        return try? CaptureManifest.decoder.decode(CaptureManifest.self, from: data)
    }

    func loadPointerCapture() -> PointerCaptureFile? {
        guard let data = try? Data(contentsOf: pointerCaptureURL) else { return nil }
        return try? CaptureManifest.decoder.decode(PointerCaptureFile.self, from: data)
    }

    func writeCaptureManifest(_ manifest: CaptureManifest) throws {
        let data = try CaptureManifest.encoder.encode(manifest)
        try data.write(to: captureManifestURL, options: .atomic)
    }

    func writePointerCapture(_ capture: PointerCaptureFile) throws {
        let data = try CaptureManifest.encoder.encode(capture)
        do {
            try data.write(to: pointerCaptureURL, options: .atomic)
        } catch {

            try data.write(to: pointerCaptureURL)
        }
    }

    func loadEditDocument() -> RecordingEditDocument? {
        guard let data = try? Data(contentsOf: editDocumentURL) else { return nil }
        return try? CaptureManifest.decoder.decode(RecordingEditDocument.self, from: data)
    }

    func writeEditDocument(_ document: RecordingEditDocument) throws {
        let data = try CaptureManifest.encoder.encode(document)
        try data.write(to: editDocumentURL, options: .atomic)
    }

    func loadDraftDocument() -> RecordingEditDocument? {
        guard let data = try? Data(contentsOf: draftDocumentURL) else { return nil }
        return try? CaptureManifest.decoder.decode(RecordingEditDocument.self, from: data)
    }

    func writeDraftDocument(_ document: RecordingEditDocument) throws {
        let data = try CaptureManifest.encoder.encode(document)
        try data.write(to: draftDocumentURL, options: .atomic)
    }

    func removeDraftDocument() {
        try? FileManager.default.removeItem(at: draftDocumentURL)
    }

    func effectiveEditDocument() -> RecordingEditDocument? {
        loadDraftDocument() ?? loadEditDocument()
    }

    var hasUnsavedDraft: Bool {
        guard let draft = loadDraftDocument() else { return false }
        return draft != loadEditDocument()
    }

    func loadProjectMetadata() -> RecordingProjectMetadata? {
        guard let data = try? Data(contentsOf: projectMetadataURL) else { return nil }
        return try? CaptureManifest.decoder.decode(RecordingProjectMetadata.self, from: data)
    }

    func writeProjectMetadata(_ metadata: RecordingProjectMetadata) {
        guard let data = try? CaptureManifest.encoder.encode(metadata) else { return }
        try? data.write(to: projectMetadataURL, options: .atomic)
    }

    func updateProjectMetadata(_ mutate: (inout RecordingProjectMetadata) -> Void) {
        var metadata = loadProjectMetadata() ?? RecordingProjectMetadata()
        metadata.version = RecordingProjectMetadata.currentVersion
        mutate(&metadata)
        writeProjectMetadata(metadata)
    }

    private struct RenderStamp: Codable {
        var layoutVersion = 1
        var document: RecordingEditDocument?
    }

    func loadRenderStamp() -> RecordingEditDocument? {
        guard let data = try? Data(contentsOf: renderStampURL) else { return nil }
        if let stamp = try? CaptureManifest.decoder.decode(RenderStamp.self, from: data) {
            return stamp.document
        }

        return try? CaptureManifest.decoder.decode(RecordingEditDocument.self, from: data)
    }

    func writeRenderStamp(_ document: RecordingEditDocument?) {
        guard let data = try? CaptureManifest.encoder.encode(RenderStamp(document: document)) else { return }
        try? data.write(to: renderStampURL, options: .atomic)
    }

    func freshFinalURL(matching document: RecordingEditDocument?) -> URL? {
        guard let existing = existingFinalURL else { return nil }
        let stamp = loadRenderStamp()

        if document?.exportAspectPreset ?? .original == .original {
            guard let data = try? Data(contentsOf: renderStampURL),
                  let stamp = try? CaptureManifest.decoder.decode(RenderStamp.self, from: data),
                  stamp.layoutVersion == 1 else { return nil }
        }
        if stamp == document { return existing }

        if let document, Self.differsOnlyByExportContainer(document, stamp) { return existing }
        return nil
    }
}

nonisolated struct CaptureManifest: Codable, Sendable, Equatable {
    var version = 1
    var createdAt = Date()

    var duration: TimeInterval = 0
    var pixelWidth = 0
    var pixelHeight = 0

    var pixelScale: Double = 1
    var sourceDisplayID: UInt32?
    var includesSystemAudio = false
    var includesMicrophone = false

    var cameraLeadIn: TimeInterval?
    var cameraWidth: Int?
    var cameraHeight: Int?

    var pointerSynthesized: Bool?

    var pressEffectsBaked: Bool?
    var pressEffectsEnabled: Bool?

    var source: CaptureSource?

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

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

nonisolated enum RecordingSessionStore {
    static var recordingsDirectory: URL {
        UpshotStorage.applicationSupportDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    static func createSession() throws -> RecordingSession {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let name = "Upshot_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6))"
        let directory = recordingsDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(RecordingSession.directoryExtension)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return RecordingSession(directoryURL: directory)
    }

    static func allSessions() -> [RecordingSession] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { RecordingSession.isSessionDirectory($0) }
            .map { RecordingSession(directoryURL: $0) }
    }

    static func deleteSession(_ session: RecordingSession) {
        try? FileManager.default.removeItem(at: session.directoryURL)
    }
}
