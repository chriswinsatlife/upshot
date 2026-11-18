//
//  RecordingProject.swift
//  Upshot
//
//  Per-project bookkeeping that lives beside the capture manifest: the name
//  shown in the Projects browser, when the project was last committed with
//  ⌘S, and when it was last opened (which orders the Recordings menu).
//  Every field is optional so a package recorded before projects existed -
//  or one whose sidecar was lost - still resolves to sensible defaults.
//

import Foundation

nonisolated struct RecordingProjectMetadata: Codable, Sendable, Equatable {
    static let currentVersion = 1

    var version: Int?
    var displayName: String?
    /// Last explicit save. Nil for a project that has only ever autosaved a
    /// draft, which is what makes "Delete and close" safe to offer.
    var savedAt: Date?
    var lastOpenedAt: Date?

    init(
        version: Int? = RecordingProjectMetadata.currentVersion,
        displayName: String? = nil,
        savedAt: Date? = nil,
        lastOpenedAt: Date? = nil
    ) {
        self.version = version
        self.displayName = displayName
        self.savedAt = savedAt
        self.lastOpenedAt = lastOpenedAt
    }
}

nonisolated struct RecordingProjectHistory: Codable {
    struct Entry: Codable {
        let actionName: String
        let before: RecordingEditDocument
        let after: RecordingEditDocument
        var usesNativeUndo = false

        private enum CodingKeys: String, CodingKey {
            case actionName, before, after
        }

        func applying(to document: RecordingEditDocument, undo: Bool) throws -> RecordingEditDocument {
            let encoder = CaptureManifest.encoder
            let old = try JSONSerialization.jsonObject(with: encoder.encode(before)) as? [String: Any] ?? [:]
            let new = try JSONSerialization.jsonObject(with: encoder.encode(after)) as? [String: Any] ?? [:]
            var target = try JSONSerialization.jsonObject(with: encoder.encode(document)) as? [String: Any] ?? [:]
            for key in Set(old.keys).union(new.keys) {
                let previous = old[key] as? NSObject
                let next = new[key] as? NSObject
                if previous != next { target[key] = undo ? old[key] : new[key] }
            }
            return try CaptureManifest.decoder.decode(
                RecordingEditDocument.self, from: JSONSerialization.data(withJSONObject: target, options: [.sortedKeys])
            )
        }
    }

    var version = 1
    let document: RecordingEditDocument
    var undo: [Entry]
    var redo: [Entry]

    private enum CodingKeys: String, CodingKey {
        case version, document, undo, redo
    }

    init(document: RecordingEditDocument, undo: [Entry], redo: [Entry]) {
        self.document = document
        self.undo = undo
        self.redo = redo
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        document = try values.decode(RecordingEditDocument.self, forKey: .document)
        undo = try values.decodeIfPresent([Entry].self, forKey: .undo) ?? []
        redo = try values.decodeIfPresent([Entry].self, forKey: .redo) ?? []
    }

    static func load(from session: RecordingSession) throws -> RecordingProjectHistory? {
        let url = session.directoryURL.appendingPathComponent(session.hasUnsavedDraft ? "undo.draft.json" : "undo.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try CaptureManifest.decoder.decode(Self.self, from: Data(contentsOf: url))
        guard value.version == 1, value.document == session.effectiveEditDocument() else {
            AppLog.event("recording", "project_undo_history_stale")
            return nil
        }
        return value
    }

    func save(to session: RecordingSession, asDraft: Bool = false) throws {
        let data = try CaptureManifest.encoder.encode(self)
        try data.write(to: session.directoryURL.appendingPathComponent(asDraft ? "undo.draft.json" : "undo.json"), options: .atomic)
    }
    static func removeDraft(from session: RecordingSession) {
        let url = session.directoryURL.appendingPathComponent("undo.draft.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch { AppLog.event("recording", "project_undo_draft_removal_failed", fields: ["error": AppLog.error(error)]) }
    }

}
