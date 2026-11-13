import AppKit
import Observation

enum CaptureHistoryFilter: String, CaseIterable, Identifiable {
    case all
    case screenshots
    case videos
    case gifs
    case videoProjects

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .screenshots: "Screenshots"
        case .videos: "Videos"
        case .gifs: "GIFs"
        case .videoProjects: "Video Projects"
        }
    }

    func includes(_ item: CaptureLibraryItem) -> Bool {
        switch self {
        case .all: true
        case .screenshots: item.session == nil && !item.isVideo && item.fileURL.pathExtension.lowercased() != "gif"
        case .videos: item.session == nil && item.isVideo && item.fileURL.pathExtension.lowercased() != "gif"
        case .gifs: item.session == nil && item.fileURL.pathExtension.lowercased() == "gif"
        case .videoProjects: item.session != nil
        }
    }

    static func kindTitle(for item: CaptureLibraryItem) -> String {
        if item.session != nil { return "Video Project" }
        if item.fileURL.pathExtension.lowercased() == "gif" { return "GIF" }
        return item.isVideo ? "Video" : "Screenshot"
    }
}

@MainActor
@Observable
final class CaptureHistoryModel {
    var filter: CaptureHistoryFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            updateVisibleItems()
            NSLog("Capture History filter=%@ visible=%ld", filter.rawValue, visibleItems.count)
        }
    }
    var selectedID: String?
    var errorMessage: String?
    private(set) var items: [CaptureLibraryItem] = []
    private(set) var visibleItems: [CaptureLibraryItem] = []
    private(set) var isLoading = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    var selectedItem: CaptureLibraryItem? {
        visibleItems.first { $0.id == selectedID }
    }

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        refreshTask = Task {
            let result = await CaptureHistoryActions.recentCaptures()
            guard !Task.isCancelled else { return }
            items = result
            isLoading = false
            updateVisibleItems()
            NSLog("Capture History loaded total=%ld visible=%ld", items.count, visibleItems.count)
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
    }

    func moveSelection(by offset: Int) {
        guard !visibleItems.isEmpty else { return }
        let current = visibleItems.firstIndex { $0.id == selectedID } ?? 0
        let index = min(max(current + offset, 0), visibleItems.count - 1)
        selectedID = visibleItems[index].id
        NSLog("Capture History selection index=%ld id=%@", index, visibleItems[index].id)
    }

    func selectBoundary(last: Bool) {
        selectedID = last ? visibleItems.last?.id : visibleItems.first?.id
    }

    func moveFilter(by offset: Int) {
        let filters = CaptureHistoryFilter.allCases
        guard let current = filters.firstIndex(of: filter) else { return }
        filter = filters[(current + offset + filters.count) % filters.count]
    }

    func restoreSelection() {
        guard let selectedItem else { return }
        if CaptureHistoryActions.restore(selectedItem) {
            CaptureHistoryPresenter.shared.dismiss()
        } else {
            errorMessage = "The capture could not be restored. The file may have moved or become unreadable."
            refresh()
        }
    }

    private func updateVisibleItems() {
        visibleItems = items.filter(filter.includes)
        if !visibleItems.contains(where: { $0.id == selectedID }) {
            selectedID = visibleItems.first?.id
        }
    }
}

@MainActor
enum CaptureHistoryActions {
    static func openCaptureHistory() {
        CaptureHistoryPresenter.shared.show()
    }

    static func restoreLastCapture() {
        Task {
            let items = await recentCaptures()
            for item in items where restore(item) {
                NSLog("Capture History restore last succeeded id=%@", item.id)
                return
            }
            NSLog("Capture History restore last unavailable")
            NSSound.beep()
        }
    }

    static func recentCaptures() async -> [CaptureLibraryItem] {
        let history = ScreenshotHistoryStore.shared.items.map(CaptureLibraryHistorySnapshot.init)
        let directory = ScreenshotHistoryStore.historyDirectory
        let activeSessionPath = ScreenRecordingManager.shared.activeSessionDirectoryURL?.standardizedFileURL.path
        let scan = Task.detached(priority: .userInitiated) {
            CaptureLibraryScanner.scan(history: history, historyDirectory: directory, excludingSessionPath: activeSessionPath)
                .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
        }
        return await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
    }

    @discardableResult
    static func restore(_ item: CaptureLibraryItem) -> Bool {
        let url = item.session?.deliverableURL ?? item.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("Capture History restore missing id=%@", item.id)
            return false
        }
        let kind: PreviewMediaKind = item.isVideo ? .video : .image
        CaptureShelf.shared.show(existing: url, kind: kind)
        guard CaptureShelf.shared.items.contains(where: { $0.url == url && $0.kind == kind }) else {
            NSLog("Capture History restore failed id=%@", item.id)
            return false
        }
        CaptureShelf.shared.open()
        CaptureShelfPresenter.shared.show(displayID: ActiveDisplayResolver.activeDisplayID())
        NSLog("Capture History restore succeeded id=%@ kind=%@", item.id, CaptureHistoryFilter.kindTitle(for: item))
        return true
    }
}
