//
//  RecordingProjectStore.swift
//  Upshot
//
//  The recent-recordings menu's model. Recording packages on disk are the source
//  of truth - not history.json - so a project whose History row was deleted
//  is still reachable, and a package deleted in Finder disappears here.
//

import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import Observation

nonisolated struct RecordingProjectSummary: Identifiable, Equatable, Sendable {
    let session: RecordingSession
    var displayName: String
    var createdAt: Date
    var duration: TimeInterval
    var pixelSize: CGSize
    /// Committed with an explicit save at least once.
    var isSaved: Bool
    /// Autosaved edits sitting on top of the saved state.
    var hasUnsavedDraft: Bool
    var sizeOnDisk: Int64
    var lastOpenedAt: Date?

    var id: URL { session.directoryURL }

    /// Orders both the Recordings menu and the browser's default sort:
    /// what you touched last, falling back to when it was recorded.
    var lastActivityAt: Date { lastOpenedAt ?? createdAt }

    var hasCamera: Bool { session.hasCamera }
}

@MainActor
@Observable
final class RecordingProjectStore {
    static let shared = RecordingProjectStore()

    private(set) var projects: [RecordingProjectSummary] = []
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    private static var posterTasks: [URL: (revision: String, id: UUID, task: Task<CGImage?, Never>)] = [:]

    /// Deliberately empty until something asks. Summarizing every package
    /// walks the Recordings folder, which is not worth doing at launch when
    /// most sessions never open the Recordings menu.
    private init() {}

    var totalSizeOnDisk: Int64 {
        projects.reduce(0) { $0 + $1.sizeOnDisk }
    }

    /// The Recordings menu shows only a handful; the rest live in Library.
    var recentProjects: [RecordingProjectSummary] {
        Array(projects.prefix(8))
    }

    func reload() {
        reloadTask?.cancel()
        reloadTask = Task {
            let scan = Task.detached(priority: .utility) {
                RecordingSessionStore.allSessions()
                    .compactMap { Task.isCancelled ? nil : Self.summarize($0) }
                    .sorted { $0.lastActivityAt > $1.lastActivityAt }
            }
            let result = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            guard !Task.isCancelled else { return }
            projects = result
        }
    }

    func rename(_ project: RecordingProjectSummary, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.session.updateProjectMetadata {
            // An emptied field falls back to the folder name rather than
            // leaving the project nameless.
            $0.displayName = trimmed.isEmpty ? nil : trimmed
        }
        reload()
    }

    /// Removes the package, the History row, and any preview card together, so
    /// no surface can disagree about whether a recording exists. The card goes
    /// first, while its files are still on disk.
    func delete(_ session: RecordingSession) {
        CaptureShelf.shared.dismissRecordingSession(session.directoryURL)
        ScreenshotHistoryStore.shared.deleteRecordingSession(session)
        RecordingSessionStore.deleteSession(session)
        reload()
    }

    func delete(_ project: RecordingProjectSummary) {
        delete(project.session)
    }

    func reveal(_ project: RecordingProjectSummary) {
        NSWorkspace.shared.activateFileViewerSelecting([project.session.directoryURL])
    }

    // MARK: - Posters

    static func poster(for session: RecordingSession) async -> NSImage? {
        guard let image = await posterImage(for: session) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    static func refreshPoster(for session: RecordingSession) {
        Task { _ = await posterImage(for: session) }
    }

    static func posterImage(for session: RecordingSession) async -> CGImage? {
        let revision = RecordingProjectPosterRevision.value(for: session)
        let stampURL = RecordingProjectPosterRevision.url(for: session)
        if let data = try? Data(contentsOf: stampURL),
           (try? JSONDecoder().decode(String.self, from: data)) == revision,
           let source = CGImageSourceCreateWithURL(session.posterURL as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return image }
        if let pending = posterTasks[session.directoryURL], pending.revision == revision {
            return await pending.task.value
        }
        posterTasks[session.directoryURL]?.task.cancel()
        let id = UUID()
        let task = Task<CGImage?, Never> {
            do {
                let configuration = try await RecordingSessionRenderer.makeConfiguration(for: session)
                try Task.checkCancellation()
                let cameraDuration = if let url = configuration.cameraURL {
                    try await AVURLAsset(url: url).load(.duration).seconds
                } else { 0.0 }
                let renderer = try RecordingProjectPreviewRenderer(configuration: configuration, cameraDuration: cameraDuration)
                let image = try await withTaskCancellationHandler {
                    try await renderer.firstFrame()
                } onCancel: { Task { await renderer.cancel() } }
                try Task.checkCancellation()
                guard RecordingProjectPosterRevision.value(for: session) == revision else { return nil }
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try jpeg.write(to: session.posterURL, options: .atomic)
                try JSONEncoder().encode(revision).write(to: stampURL, options: .atomic)
                AppLog.event("library", "project_poster_generated", fields: [
                    "item": AppLog.identifier(session.directoryURL.path),
                    "width": String(image.width), "height": String(image.height)
                ])
                return image
            } catch is CancellationError {
                return nil
            } catch {
                guard !Task.isCancelled else { return nil }
                AppLog.event("library", "project_poster_failed", fields: [
                    "item": AppLog.identifier(session.directoryURL.path), "error": AppLog.error(error)
                ])
                let fallback = session.freshFinalURL(matching: session.effectiveEditDocument()) ?? session.screenURL
                guard let image = await VideoPreviewImageLoader.thumbnail(at: fallback, maxPixelSize: 640) else { return nil }
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
        }
        posterTasks[session.directoryURL] = (revision, id, task)
        let image = await task.value
        if posterTasks[session.directoryURL]?.id == id {
            posterTasks.removeValue(forKey: session.directoryURL)
        }
        return image
    }

    // MARK: - Summaries

    nonisolated private static func summarize(_ session: RecordingSession) -> RecordingProjectSummary {
        let manifest = session.loadCaptureManifest()
        let metadata = session.loadProjectMetadata()
        let folderCreatedAt = try? session.directoryURL
            .resourceValues(forKeys: [.creationDateKey])
            .creationDate
        let createdAt = manifest?.createdAt ?? folderCreatedAt ?? Date.distantPast

        return RecordingProjectSummary(
            session: session,
            displayName: session.displayName,
            createdAt: createdAt,
            duration: manifest?.duration ?? 0,
            pixelSize: CGSize(
                width: manifest?.pixelWidth ?? 0,
                height: manifest?.pixelHeight ?? 0
            ),
            isSaved: session.hasSavedProject,
            hasUnsavedDraft: session.hasUnsavedDraft,
            sizeOnDisk: sizeOnDisk(of: session.directoryURL),
            lastOpenedAt: metadata?.lastOpenedAt
        )
    }

    nonisolated private static func sizeOnDisk(of directoryURL: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard !Task.isCancelled else { return total }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }
}

/// Opening a project has to reach the `VIDEO_EDITOR` scene from AppKit-hosted
/// surfaces such as the menu bar extra, which have no scene
/// environment of their own. `UpshotApp` installs the opener, mirroring
/// what `CaptureShelfPresenter.onEditVideo` already does.
@MainActor
final class RecordingProjectOpener {
    static let shared = RecordingProjectOpener()

    var openHandler: ((URL) -> Void)?

    private init() {}

    func open(_ session: RecordingSession) {
        RecordingProjectStore.shared.reload()
        openHandler?(session.directoryURL)
    }
}

/// Knows which Studio windows are currently holding uncommitted edits, so
/// quitting can say so.
@MainActor
final class StudioProjectRegistry {
    static let shared = StudioProjectRegistry()

    private var models: [ObjectIdentifier: WeakModel] = [:]

    private struct WeakModel {
        weak var model: RecordingStudioModel?
    }

    private init() {}

    func register(_ model: RecordingStudioModel) {
        models[ObjectIdentifier(model)] = WeakModel(model: model)
    }

    func unregister(_ model: RecordingStudioModel) {
        models.removeValue(forKey: ObjectIdentifier(model))
    }

    func hasLoadedEditor(for url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return models.values.contains {
            guard let model = $0.model, model.isLoaded, !model.isAgentSession else { return false }
            return model.sessionURL.standardizedFileURL.path == path
        }
    }

    /// The model a Studio window is editing this project in, if one is open.
    func editorModel(for url: URL) -> RecordingStudioModel? {
        let path = url.standardizedFileURL.path
        return models.values.lazy.compactMap(\.model).first {
            $0.isLoaded && !$0.isAgentSession && $0.sessionURL.standardizedFileURL.path == path
        }
    }

    var unsavedProjectCount: Int {
        models.values.compactMap(\.model).filter(\.hasUnsavedChanges).count
    }

    /// Called before the app goes away. The autosave is debounced, so without
    /// this a quit can drop the last fraction of a second of edits.
    func flushDrafts() {
        for model in models.values.compactMap(\.model) {
            model.flushDraft()
        }
    }
}
