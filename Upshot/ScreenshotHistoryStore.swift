import AppKit
import AVFoundation
@preconcurrency import CoreMedia
import Observation

struct ScreenshotHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var fileName: String
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: PreviewMediaKind
    var duration: Double?
    var cloudURL: String?
    var hasEdits: Bool
    var recordingSessionPath: String?
    var displayName: String?
    var source: CaptureSource?

    var recordingSession: RecordingSession? {
        guard let recordingSessionPath else { return nil }
        let session = RecordingSession(directoryURL: URL(fileURLWithPath: recordingSessionPath, isDirectory: true))
        return RecordingSession.isSessionDirectory(session.directoryURL) ? session : nil
    }

    var url: URL {
        if let recordingSession {
            return recordingSession.deliverableURL
        }
        return ScreenshotHistoryStore.historyDirectory.appendingPathComponent(fileName)
    }

    var editorURL: URL {
        recordingSession?.directoryURL ?? url
    }

    var isVideo: Bool { kind == .video }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        fileName = try container.decode(String.self, forKey: .fileName)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        kind = try container.decodeIfPresent(PreviewMediaKind.self, forKey: .kind) ?? .image
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        cloudURL = try container.decodeIfPresent(String.self, forKey: .cloudURL)
        hasEdits = try container.decodeIfPresent(Bool.self, forKey: .hasEdits) ?? false
        recordingSessionPath = try container.decodeIfPresent(String.self, forKey: .recordingSessionPath)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        source = try container.decodeIfPresent(CaptureSource.self, forKey: .source)
    }

    init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        fileName: String,
        pixelWidth: Int,
        pixelHeight: Int,
        kind: PreviewMediaKind = .image,
        duration: Double? = nil,
        cloudURL: String? = nil,
        hasEdits: Bool = false,
        recordingSessionPath: String? = nil,
        displayName: String? = nil,
        source: CaptureSource? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
        self.duration = duration
        self.cloudURL = cloudURL
        self.hasEdits = hasEdits
        self.recordingSessionPath = recordingSessionPath
        self.displayName = displayName
        self.source = source
    }
}

@MainActor
@Observable
final class ScreenshotHistoryStore {
    static let shared = ScreenshotHistoryStore()

    static var applicationSupportDirectory: URL {
        UpshotStorage.applicationSupportDirectory
    }

    static var historyDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("History", isDirectory: true)
    }

    private static var metadataURL: URL {
        applicationSupportDirectory.appendingPathComponent("history.json")
    }

    static func editDocumentURL(for displayURL: URL) -> URL {
        displayURL.appendingPathExtension("upshot")
    }

    static func baseImageURL(for displayURL: URL) -> URL {
        let ext = displayURL.pathExtension
        let stem = displayURL.deletingPathExtension().lastPathComponent
        let directory = displayURL.deletingLastPathComponent()
        let fileName = ext.isEmpty ? "\(stem).base" : "\(stem).base.\(ext)"
        return directory.appendingPathComponent(fileName)
    }

    func loadEditDocument(for displayURL: URL) -> AnnotationDocument? {
        let documentURL = Self.editDocumentURL(for: displayURL)
        guard let data = try? Data(contentsOf: documentURL),
              let document = try? JSONDecoder().decode(AnnotationDocument.self, from: data) else {
            return nil
        }
        return document
    }

    func hasEditDocument(for displayURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: Self.editDocumentURL(for: displayURL).path)
    }

    private(set) var items: [ScreenshotHistoryItem] = []

    var recentItems: [ScreenshotHistoryItem] {
        Array(items.prefix(5))
    }

    private init() {
        load()
        Task { CaptureHistoryRetention.shared.start() }
    }

    @discardableResult
    func importScreenshot(from sourceURL: URL, source: CaptureSource? = nil) -> URL {
        do {
            try FileManager.default.createDirectory(at: Self.historyDirectory, withIntermediateDirectories: true)
            let destinationURL = ScreenshotFileNaming.uniqueURL(
                fileName: ScreenshotFileNaming.historyFileName(for: sourceURL),
                in: Self.historyDirectory
            )

            if sourceURL != destinationURL {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }

            let imageSize = ScreenshotImageLoader.imageSize(at: destinationURL) ?? .zero
            let item = ScreenshotHistoryItem(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                fileName: destinationURL.lastPathComponent,
                pixelWidth: Int(imageSize.width),
                pixelHeight: Int(imageSize.height),
                source: source
            )
            items.insert(item, at: 0)
            saveMetadata()
            return destinationURL
        } catch {
            print("Failed to import screenshot into history: \(error)")
            return sourceURL
        }
    }

    @discardableResult
    func importVideo(from sourceURL: URL) async -> URL {
        do {
            try FileManager.default.createDirectory(at: Self.historyDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueHistoryURL(for: sourceURL)

            if sourceURL != destinationURL {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }

            let metadata = await videoMetadata(at: destinationURL)

            let item = ScreenshotHistoryItem(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                fileName: destinationURL.lastPathComponent,
                pixelWidth: metadata.width,
                pixelHeight: metadata.height,
                kind: .video,
                duration: metadata.duration
            )
            items.insert(item, at: 0)
            saveMetadata()
            return destinationURL
        } catch {
            print("Failed to import video into history: \(error)")
            return sourceURL
        }
    }

    @discardableResult
    func importRecordingSession(_ session: RecordingSession) async -> URL {
        let standardizedPath = session.directoryURL.standardizedFileURL.path
        if let existing = items.first(where: { $0.recordingSessionPath == standardizedPath }) {
            return existing.url
        }
        guard RecordingSession.isSessionDirectory(session.directoryURL) else {
            return session.screenURL
        }

        let manifest = session.loadCaptureManifest()
        let metadata: (width: Int, height: Int, duration: Double?)
        if let manifest,
           manifest.pixelWidth > 0,
           manifest.pixelHeight > 0,
           manifest.duration > 0 {
            metadata = (
                width: manifest.pixelWidth,
                height: manifest.pixelHeight,
                duration: manifest.duration
            )
        } else {
            metadata = await videoMetadata(at: session.screenURL)
        }
        let displayName = session.directoryURL
            .deletingPathExtension()
            .lastPathComponent
            .appending(".\(VideoExportContainer.default.fileExtension)")
        let item = ScreenshotHistoryItem(
            id: UUID(),
            createdAt: manifest?.createdAt ?? Date(),
            updatedAt: Date(),
            fileName: displayName,
            pixelWidth: metadata.width,
            pixelHeight: metadata.height,
            kind: .video,
            duration: metadata.duration,
            recordingSessionPath: standardizedPath
        )
        items.insert(item, at: 0)
        saveMetadata()
        return session.deliverableURL
    }

    @discardableResult
    func commitAnnotations(
        displayURL: URL,
        baseURL: URL,
        renderedURL: URL,
        document: AnnotationDocument
    ) throws -> URL {
        guard isHistoryURL(displayURL) else {
            let imported = importScreenshot(from: baseURL)
            guard isHistoryURL(imported) else { throw CocoaError(.fileWriteUnknown) }
            return try commitAnnotations(displayURL: imported, baseURL: baseURL,
                                         renderedURL: renderedURL, document: document)
        }
        let baseDestination = Self.baseImageURL(for: displayURL)
        var replacements: [(source: URL, destination: URL)] = []
        if baseURL.standardizedFileURL != baseDestination.standardizedFileURL {
            if baseURL.standardizedFileURL != displayURL.standardizedFileURL
                || !FileManager.default.fileExists(atPath: baseDestination.path) {
                replacements.append((baseURL, baseDestination))
            }
        }
        var document = document
        document.baseImageFileName = baseDestination.lastPathComponent
        let documentData = try JSONEncoder().encode(document)
        let temporaryDocument = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try documentData.write(to: temporaryDocument, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryDocument) }
        replacements.append((renderedURL, displayURL))
        replacements.append((temporaryDocument, Self.editDocumentURL(for: displayURL)))
        try ScreenshotEditFileTransaction.apply(replacements: replacements)

        if let index = items.firstIndex(where: { $0.fileName == displayURL.lastPathComponent }) {
            let imageSize = ScreenshotImageLoader.imageSize(at: displayURL) ?? .zero
            items[index].updatedAt = Date()
            items[index].pixelWidth = Int(imageSize.width)
            items[index].pixelHeight = Int(imageSize.height)
            items[index].hasEdits = true
            saveMetadata()
        }
        return displayURL
    }

    @discardableResult
    func removeAnnotations(displayURL: URL) throws -> URL {
        guard isHistoryURL(displayURL) else { return displayURL }
        let baseDestination = Self.baseImageURL(for: displayURL)
        let documentURL = Self.editDocumentURL(for: displayURL)
        guard FileManager.default.fileExists(atPath: baseDestination.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        try ScreenshotEditFileTransaction.apply(
            replacements: [(baseDestination, displayURL)],
            removing: [baseDestination, documentURL]
        )
        if let index = items.firstIndex(where: { $0.fileName == displayURL.lastPathComponent }) {
            let imageSize = ScreenshotImageLoader.imageSize(at: displayURL) ?? .zero
            items[index].updatedAt = Date()
            items[index].pixelWidth = Int(imageSize.width)
            items[index].pixelHeight = Int(imageSize.height)
            items[index].hasEdits = false
            saveMetadata()
        }
        return displayURL
    }

    func delete(_ item: ScreenshotHistoryItem) {
        let auxiliaryURLs: [URL]
        if let recordingSession = item.recordingSession {
            auxiliaryURLs = [recordingSession.directoryURL]
        } else {
            auxiliaryURLs = [
                item.url,
                Self.baseImageURL(for: item.url),
                Self.editDocumentURL(for: item.url)
            ]
        }

        for url in auxiliaryURLs where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Failed to delete history file: \(error)")
            }
        }

        let wasRecordingProject = item.recordingSessionPath != nil
        items.removeAll { $0.id == item.id }
        saveMetadata()
        if wasRecordingProject {
            RecordingProjectStore.shared.reload()
        }
    }

    func deleteRecordingSession(_ session: RecordingSession) {
        let standardizedPath = session.directoryURL.standardizedFileURL.path
        guard items.contains(where: { $0.recordingSessionPath == standardizedPath }) else {
            return
        }
        items.removeAll { $0.recordingSessionPath == standardizedPath }
        saveMetadata()
    }

    @discardableResult
    func delete(url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        guard let item = items.first(where: { $0.url.standardizedFileURL == standardizedURL }) else {
            return false
        }

        delete(item)
        return true
    }

    func setCloudURL(for fileURL: URL, cloudURL: String) {
        let standardized = fileURL.standardizedFileURL
        guard let index = items.firstIndex(where: { $0.url.standardizedFileURL == standardized }) else {
            return
        }
        items[index].cloudURL = cloudURL
        items[index].updatedAt = Date()
        saveMetadata()
    }

    func clearCloudURL(for fileURL: URL) {
        let standardized = fileURL.standardizedFileURL
        guard let index = items.firstIndex(where: { $0.url.standardizedFileURL == standardized }) else {
            return
        }
        items[index].cloudURL = nil
        items[index].updatedAt = Date()
        saveMetadata()
    }

    func reveal(_ item: ScreenshotHistoryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([
            item.recordingSession?.directoryURL ?? item.url
        ])
    }

    func editorURL(for mediaURL: URL) -> URL {
        let standardizedURL = mediaURL.standardizedFileURL
        return items.first(where: { $0.url.standardizedFileURL == standardizedURL })?.editorURL
            ?? RecordingDeliverable.session(for: standardizedURL)?.directoryURL
            ?? mediaURL
    }

    func reload() {
        load()
    }

    func rename(id: UUID, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].displayName = trimmed.isEmpty ? nil : trimmed
        items[index].updatedAt = Date()
        saveMetadata()
    }

    func removeTrashedItems(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        saveMetadata()
    }

    func setLibraryCloudURL(id: UUID, cloudURL: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].cloudURL = cloudURL
        items[index].updatedAt = Date()
        saveMetadata()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.metadataURL),
              let decoded = try? JSONDecoder().decode([ScreenshotHistoryItem].self, from: data) else {
            items = []
            return
        }

        items = decoded
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func saveMetadata() {
        do {
            try FileManager.default.createDirectory(at: Self.applicationSupportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: Self.metadataURL, options: .atomic)
        } catch {
            print("Failed to save screenshot history: \(error)")
        }
    }

    private func uniqueHistoryURL(for sourceURL: URL) -> URL {
        let pathExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let fileName = ScreenshotFileNaming.fileName(extension: pathExtension)
        let initialURL = Self.historyDirectory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        let baseName = initialURL.deletingPathExtension().lastPathComponent
        for index in 1...10_000 {
            let candidateURL = Self.historyDirectory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(pathExtension)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return Self.historyDirectory
            .appendingPathComponent("Upshot_\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }

    private func videoMetadata(at url: URL) async -> (width: Int, height: Int, duration: Double?) {
        let asset = AVURLAsset(url: url)
        var width = 0
        var height = 0
        var duration: Double?

        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let size = try? await track.load(.naturalSize)
            let transform = try? await track.load(.preferredTransform)
            if let size, let transform {
                let transformed = size.applying(transform)
                width = Int(abs(transformed.width))
                height = Int(abs(transformed.height))
            } else if let size {
                width = Int(size.width)
                height = Int(size.height)
            }
        }

        if let loadedDuration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(loadedDuration)
            if seconds.isFinite, seconds > 0 {
                duration = seconds
            }
        }
        return (width, height, duration)
    }

    private func isHistoryURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(Self.historyDirectory.standardizedFileURL.path)
    }

}
