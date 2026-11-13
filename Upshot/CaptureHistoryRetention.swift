import AppKit

@MainActor
final class CaptureHistoryRetention {
    static let shared = CaptureHistoryRetention()

    private var maintenanceTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var preferencesObserver: NSObjectProtocol?
    private var observedRetentionDays = 0

    private init() {}

    func start() {
        guard maintenanceTask == nil else { return }
        observedRetentionDays = UpshotPreferences.historyRetentionDays
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let days = UpshotPreferences.historyRetentionDays
                guard days != self.observedRetentionDays else { return }
                self.observedRetentionDays = days
                self.scheduleCleanup()
            }
        }
        scheduleCleanup()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3600)) }
                catch { return }
                self?.scheduleCleanup()
            }
        }
        AppLog.event("library", "capture_history_retention_started", fields: ["days": String(describing: observedRetentionDays), "interval": "3600"])
    }

    func scheduleCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard let self, UpshotPreferences.historyRetentionDays > 0 else { return }
            let captures = await CaptureHistoryActions.recentCaptures()
            guard !Task.isCancelled else { return }
            self.removeExpiredCaptures(from: captures, retentionDays: UpshotPreferences.historyRetentionDays, now: Date())
        }
    }

    func removeExpiredCaptures(from captures: [CaptureLibraryItem], retentionDays: Int, now: Date) {
        guard retentionDays > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else { return }
        let candidates = captures.filter { $0.createdAt > .distantPast && $0.createdAt < cutoff }
        var removedIDs: Set<UUID> = []
        var removedCount = 0
        var protectedCount = 0
        var failedCount = 0
        for item in candidates {
            let activeSession = ScreenRecordingManager.shared.activeSessionDirectoryURL?.standardizedFileURL
            guard item.ownedURL.standardizedFileURL != activeSession,
                  !CaptureLibraryOpenEditors.isEditing(item.ownedURL),
                  !CaptureLibraryOpenEditors.isEditing(item.fileURL),
                  !StudioProjectRegistry.shared.hasLoadedEditor(for: item.ownedURL) else {
                protectedCount += 1
                AppLog.event("library", "capture_history_retention_protected_editor_or_recording", fields: ["id": AppLog.identifier(String(describing: item.id))])
                continue
            }
            do {
                try CaptureLibraryFiles.trash(item)
                removedIDs.formUnion(item.historyIDs)
                removedCount += 1
                if let session = item.session {
                    CaptureShelf.shared.dismissRecordingSession(session.directoryURL)
                } else {
                    let cards = CaptureShelf.shared.items.filter { $0.url.standardizedFileURL == item.fileURL.standardizedFileURL }
                    for card in cards { CaptureShelf.shared.dismiss(id: card.id) }
                }
                AppLog.event("library", "capture_history_retention_trashed", fields: ["id": AppLog.identifier(String(describing: item.id))])
            } catch {
                failedCount += 1
                AppLog.event("library", "capture_history_retention_failed", fields: ["error": AppLog.error(error), "id": AppLog.identifier(String(describing: item.id))])
            }
        }
        if removedCount > 0 {
            ScreenshotHistoryStore.shared.removeTrashedItems(ids: removedIDs)
            RecordingProjectStore.shared.reload()
            CaptureLibraryModel.shared.refresh()
        }
        AppLog.event("library", "capture_history_retention_completed", fields: ["candidates": String(describing: candidates.count), "days": String(describing: retentionDays), "failed": String(describing: failedCount), "protected": String(describing: protectedCount), "trashed": String(describing: removedCount)])
    }
}
