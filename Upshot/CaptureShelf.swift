import AppKit
import Observation
import SwiftUI

enum PreviewMediaKind: String, Equatable, Codable {
    case image
    case video
}

enum ShelfActivity: Equatable {
    case compressing
    case preparing
}

enum ShelfFlash: Equatable {
    case linkCopied
    case uploadFailed
    case compressed(summary: String)
    case actionFailed(message: String)
}

struct ShelfItem: Identifiable {
    let id = UUID()
    var url: URL
    var thumbnail: NSImage
    var kind: PreviewMediaKind = .image
    var savedURL: URL?
    var activity: ShelfActivity?
    var flash: ShelfFlash?
    var isEngaged = false
}

@MainActor
@Observable
final class CaptureShelf {
    static let shared = CaptureShelf()

    enum TuckReason: Hashable {
        case user
        case editor
    }

    private(set) var items: [ShelfItem] = []
    private(set) var tuckReasons: Set<TuckReason> = []
    var hoveredID: ShelfItem.ID?
    private(set) var draggingID: ShelfItem.ID?
    private(set) var isMoving = false

    @ObservationIgnored var capacity = 6 {
        didSet { trimToCapacity() }
    }

    @ObservationIgnored private var autoCloseTasks: [ShelfItem.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var flashTasks: [ShelfItem.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var compressionTasks: [ShelfItem.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var keepCardAfterDrag = false

    private init() {}

    var isTucked: Bool { !tuckReasons.isEmpty }

    var hoveredItem: ShelfItem? {
        hoveredID.flatMap(item(id:))
    }

    var unsavedItems: [ShelfItem] {
        items.filter { $0.savedURL == nil }
    }

    func item(id: ShelfItem.ID) -> ShelfItem? {
        items.first { $0.id == id }
    }


    func tuck(_ reason: TuckReason) {
        guard !tuckReasons.contains(reason) else { return }
        noteMotion()
        withAnimation(Self.slideIfAllowed) {
            _ = tuckReasons.insert(reason)
            hoveredID = nil
        }
    }

    func untuck(_ reason: TuckReason) {
        guard tuckReasons.contains(reason) else { return }
        noteMotion()
        withAnimation(Self.slideIfAllowed) {
            _ = tuckReasons.remove(reason)
        }
    }

    func open() {
        guard isTucked else { return }
        noteMotion()
        withAnimation(Self.slideIfAllowed) {
            tuckReasons.removeAll()
        }
    }


    func add(url: URL) {
        let showsCard = AfterCaptureActions.isEnabled(.showOverlay, for: .screenshot)
        let savedURL = AfterCaptureActions.isEnabled(.save, for: .screenshot)
            ? saveToDefaultLocation(from: url)
            : nil

        guard showsCard,
              let thumbnail = ScreenshotImageLoader.downsampledImage(at: url, maxPixelSize: Self.thumbnailPixelSize)
        else {
            runAfterCaptureActions(type: .screenshot, url: url, itemID: nil)
            return
        }

        let item = ShelfItem(url: url, thumbnail: thumbnail, savedURL: savedURL)
        insert(item)
        runAfterCaptureActions(type: .screenshot, url: url, itemID: item.id)
        scheduleAutoClose(id: item.id)
    }

    func addVideo(url: URL) {
        guard AfterCaptureActions.isEnabled(.showOverlay, for: .recording) else {
            if AfterCaptureActions.isEnabled(.save, for: .recording) {
                Task { _ = await saveVideoToDefaultLocation(from: url, itemID: nil) }
            }
            runAfterCaptureActions(type: .recording, url: url, itemID: nil)
            return
        }

        let item = ShelfItem(url: url, thumbnail: VideoPreviewImageLoader.placeholderImage(), kind: .video)
        let id = item.id
        insert(item)
        loadVideoThumbnail(for: id, from: url)
        runAfterCaptureActions(type: .recording, url: url, itemID: id)
        scheduleAutoClose(id: id)

        if AfterCaptureActions.isEnabled(.save, for: .recording) {
            Task {
                let savedURL = await saveVideoToDefaultLocation(from: url, itemID: id)
                update(id) { $0.savedURL = savedURL }
            }
        }
    }

    func show(existing url: URL, kind: PreviewMediaKind) {
        if let index = items.firstIndex(where: { $0.url == url && $0.kind == kind }) {
            noteMotion()
        withAnimation(Self.slideIfAllowed) {
                let item = items.remove(at: index)
                items.insert(item, at: 0)
                tuckReasons.removeAll()
            }
            return
        }

        switch kind {
        case .image:
            guard let thumbnail = ScreenshotImageLoader.downsampledImage(at: url, maxPixelSize: Self.thumbnailPixelSize) else { return }
            insert(ShelfItem(url: url, thumbnail: thumbnail))
        case .video:
            let item = ShelfItem(url: url, thumbnail: VideoPreviewImageLoader.placeholderImage(), kind: .video)
            insert(item)
            loadVideoThumbnail(for: item.id, from: url)
        }
    }

    @discardableResult
    func applyAnnotation(originalURL: URL, historyURL: URL, addsIfMissing: Bool = false) -> Bool {
        if let existing = items.first(where: { $0.url == originalURL }) {
            guard let thumbnail = ScreenshotImageLoader.downsampledImage(at: historyURL, maxPixelSize: Self.thumbnailPixelSize) else {
                return true
            }
            CloudUploader.shared.clearUploadState(for: existing.id)
            update(existing.id) {
                $0.url = historyURL
                $0.thumbnail = thumbnail
            }
            republish(existing.id)
            return true
        }

        guard addsIfMissing,
              let thumbnail = ScreenshotImageLoader.downsampledImage(at: historyURL, maxPixelSize: Self.thumbnailPixelSize)
        else {
            if UpshotPreferences.autoCopy {
                _ = copyImageToClipboard(historyURL)
            }
            return false
        }
        let item = ShelfItem(url: historyURL, thumbnail: thumbnail)
        insert(item)
        republish(item.id)
        return false
    }


    func dismiss(id: ShelfItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if QuickLookPreviewPresenter.currentURL == items[index].url {
            QuickLookPreviewPresenter.dismiss()
        }
        cancelTasks(for: id)

        noteMotion()
        withAnimation(Self.slideIfAllowed) {
            items.remove(at: index)
            if hoveredID == id { hoveredID = nil }
            if draggingID == id { draggingID = nil }
            if items.isEmpty { tuckReasons.removeAll() }
        } completion: {
            CaptureShelfPresenter.shared.closeIfEmpty()
        }
    }

    func dismissAll() {
        QuickLookPreviewPresenter.dismiss()
        for id in items.map(\.id) { cancelTasks(for: id) }

        noteMotion()
        withAnimation(Self.slideIfAllowed) {
            items.removeAll()
            tuckReasons.removeAll()
            hoveredID = nil
            draggingID = nil
        } completion: {
            CaptureShelfPresenter.shared.closeIfEmpty()
        }
    }

    func dismissVideo(for url: URL) {
        if RecordingSession.isSessionDirectory(url) {
            dismissRecordingSession(url)
        } else if let session = RecordingDeliverable.session(for: url) {
            dismissRecordingSession(session.directoryURL)
        } else {
            let standardizedURL = url.standardizedFileURL
            for item in items where item.kind == .video && item.url.standardizedFileURL == standardizedURL {
                dismiss(id: item.id)
            }
        }
    }

    func dismissRecordingSession(_ directoryURL: URL) {
        let packagePath = directoryURL.standardizedFileURL.path
        let prefix = packagePath.hasSuffix("/") ? packagePath : packagePath + "/"
        for item in items where item.kind == .video && item.url.standardizedFileURL.path.hasPrefix(prefix) {
            dismiss(id: item.id)
        }
    }


    func setHovered(_ id: ShelfItem.ID, _ isHovered: Bool) {
        if isHovered {
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    func beginDrag(id: ShelfItem.ID) {
        guard draggingID != id else { return }
        QuickLookPreviewPresenter.dismiss()
        keepCardAfterDrag = NSEvent.modifierFlags.contains(.option)
        engage(id)
        draggingID = id
        NSLog("Quick Access drag item=%@ keepWithOption=%@ outcome=started", id.uuidString, keepCardAfterDrag.description)
    }

    func endDrag(id: ShelfItem.ID, operation: DropOperation) {
        let completed = operation != .cancel && operation != .forbidden
        let keepWithOption = keepCardAfterDrag || NSEvent.modifierFlags.contains(.option)
        keepCardAfterDrag = false
        if completed && !keepWithOption && UpshotPreferences.previewCloseAfterDragging {
            dismiss(id: id)
            NSLog("Quick Access drag item=%@ outcome=completed card=closed", id.uuidString)
        } else {
            withAnimation(.morphQuickIfAllowed) { draggingID = nil }
            NSLog("Quick Access drag item=%@ outcome=%@ keepWithOption=%@ card=retained", id.uuidString, completed ? "completed" : "cancelled", keepWithOption.description)
        }
    }


    @discardableResult
    static func performHoveredAction(_ action: OverlayCardAction) -> Bool {
        let shelf = shared
        guard !shelf.isTucked, !shelf.isMoving, shelf.draggingID == nil,
              let item = shelf.hoveredItem else { return false }
        return shelf.perform(action, id: item.id)
    }

    func canPerform(_ action: OverlayCardAction, id: ShelfItem.ID) -> Bool {
        guard let item = item(id: id), item.activity == nil, draggingID == nil,
              !CloudUploader.shared.uploadingItems.contains(id) else { return false }
        if (action == .pin || action == .compress) && item.kind != .image { return false }
        if action == .delete && isOpenInEditor(id: id) { return false }
        if action == .upload && !CloudUploader.shared.isConfigured { return false }
        return true
    }

    @discardableResult
    func perform(_ action: OverlayCardAction, id: ShelfItem.ID) -> Bool {
        guard canPerform(action, id: id) else { return false }

        switch action {
        case .copy: copy(id: id)
        case .compress: compress(id: id)
        case .save: save(id: id)
        case .pin: pin(id: id)
        case .annotate: openEditor(id: id)
        case .view: quickLook(id: id)
        case .upload:
            if CloudUploader.shared.uploadedURLs[id] == nil {
                upload(id: id)
            } else {
                copyLink(id: id)
            }
        case .delete: delete(id: id)
        case .close: dismiss(id: id)
        }
        return true
    }

    func openEditor(id: ShelfItem.ID) {
        guard let item = item(id: id) else { return }
        engage(id)
        QuickLookPreviewPresenter.dismiss()
        switch item.kind {
        case .image: CaptureShelfPresenter.shared.onAnnotate?(item.url)
        case .video: CaptureShelfPresenter.shared.onEditVideo?(item.url)
        }
    }

    func quickLook(id: ShelfItem.ID) {
        guard let item = item(id: id) else { return }
        engage(id)
        QuickLookPreviewPresenter.show(url: item.url)
    }

    func copy(id: ShelfItem.ID) {
        guard let item = item(id: id) else { return }
        switch item.kind {
        case .image:
            guard copyImageToClipboard(item.url) else { return }
            dismiss(id: id)
        case .video:
            Task {
                guard await copyVideoToClipboard(item.url, itemID: id) else { return }
                dismiss(id: id)
            }
        }
    }

    func pin(id: ShelfItem.ID) {
        guard let item = item(id: id), item.kind == .image else { return }
        QuickLookPreviewPresenter.dismiss()
        PinnedScreenshotPresenter.shared.pin(url: item.url)
        dismiss(id: id)
    }

    func isOpenInEditor(id: ShelfItem.ID) -> Bool {
        guard let item = item(id: id) else { return false }
        return CaptureLibraryOpenEditors.isEditing(item.url)
    }

    func delete(id: ShelfItem.ID) {
        guard let item = item(id: id), !isOpenInEditor(id: id) else { return }
        if !ScreenshotHistoryStore.shared.delete(url: item.url) {
            deleteFile(at: item.url)
        }
        if let savedURL = item.savedURL, savedURL != item.url {
            deleteFile(at: savedURL)
        }
        dismiss(id: id)
    }

    func copyText(id: ShelfItem.ID) {
        guard let item = item(id: id), item.kind == .image else { return }
        let url = item.url
        Task {
            await CaptureTextActions.copyText(at: url)
        }
    }

    func upload(id: ShelfItem.ID) {
        guard let item = item(id: id), CloudUploader.shared.isConfigured,
              !CloudUploader.shared.uploadingItems.contains(id) else { return }
        engage(id)
        let url = item.url
        NSLog("Quick Access upload item=%@ outcome=started", id.uuidString)
        Task {
            do {
                let result = try await CloudUploader.shared.upload(
                    itemID: id,
                    fileURL: url,
                    socialEnabled: CloudUploadPreferences.lastSocialEnabled
                )
                copyString(result.url)
                ScreenshotHistoryStore.shared.setCloudURL(for: url, cloudURL: result.url)
                guard self.item(id: id)?.url == url else {
                    NSLog("Quick Access upload item=%@ outcome=succeeded card=changedOrRemoved", id.uuidString)
                    return
                }
                if UpshotPreferences.previewCloseAfterUploading {
                    dismiss(id: id)
                    NSLog("Quick Access upload item=%@ outcome=succeeded card=closed", id.uuidString)
                } else {
                    flash(.linkCopied, on: id)
                    NSLog("Quick Access upload item=%@ outcome=succeeded card=retained", id.uuidString)
                }
            } catch is CancellationError {
                NSLog("Quick Access upload item=%@ outcome=cancelled card=retained", id.uuidString)
                return
            } catch {
                CloudUploader.shared.clearFailed(for: id)
                if self.item(id: id)?.url == url {
                    flash(.uploadFailed, on: id)
                }
                NSLog("Quick Access upload item=%@ outcome=failed card=retained error=%@", id.uuidString, error.localizedDescription)
            }
        }
    }

    func copyLink(id: ShelfItem.ID) {
        guard let link = CloudUploader.shared.uploadedURLs[id] else { return }
        copyString(link)
        flash(.linkCopied, on: id)
    }

    func save(id: ShelfItem.ID, choosingLocation: Bool = false) {
        guard let item = item(id: id) else { return }
        engage(id)

        if !choosingLocation && UpshotPreferences.saveButtonUsesConfiguredFolder {
            guard item.savedURL == nil else {
                dismiss(id: id)
                return
            }
            switch item.kind {
            case .video:
                Task {
                    guard let savedURL = await saveVideoToDefaultLocation(from: item.url, itemID: id) else { return }
                    update(id) { $0.savedURL = savedURL }
                    dismiss(id: id)
                }
            case .image:
                do {
                    let savedURL = try ScreenshotFileActions.saveToDefaultLocation(from: item.url)
                    update(id) { $0.savedURL = savedURL }
                    dismiss(id: id)
                } catch {
                    presentSaveFailure(error, id: id)
                }
            }
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = item.kind == .video
            ? VideoExportContainer.allCases.map(\.contentType)
            : [ScreenshotFileActions.exportContentType]
        panel.nameFieldStringValue = item.kind == .video
            ? VideoFileActions.exportFileName(for: item.url)
            : ScreenshotFileActions.exportFileName(for: item.url)
        panel.canCreateDirectories = true
        panel.title = item.kind == .video ? "Save Recording" : "Save Screenshot"

        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    if item.kind == .video {
                        let deliverable = try await self.prepareDeliverable(from: item.url, itemID: id)
                        try await VideoFileActions.save(from: deliverable, to: destination)
                    } else {
                        try ScreenshotFileActions.save(from: item.url, to: destination)
                    }
                    self.update(id) { $0.savedURL = destination }
                    self.dismiss(id: id)
                } catch {
                    FailureAlert.present(message: "The capture could not be saved", error: error)
                }
            }
        }
    }

    func compress(id: ShelfItem.ID) {
        guard let item = item(id: id), item.kind == .image, item.activity == nil else { return }
        engage(id)
        QuickLookPreviewPresenter.dismiss()
        update(id) { $0.activity = .compressing }

        let sourceURL = item.url
        let quality = ScreenshotCompressionService.defaultJPEGQuality
        compressionTasks[id] = Task {
            defer {
                compressionTasks[id] = nil
                update(id) { $0.activity = nil }
            }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ScreenshotCompressionService.compressToTemporaryJPEG(sourceURL: sourceURL, quality: quality)
                }.value
                try Task.checkCancellation()
                insertCompressed(result, beside: id)
            } catch is CancellationError {
                return
            } catch {
                print("Failed to compress screenshot: \(error)")
            }
        }
    }


    static let slide = Animation.smooth(duration: 0.38)

    static var slideIfAllowed: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : slide
    }

    @ObservationIgnored private var motionEndTask: Task<Void, Never>?

    func noteMotion() {
        isMoving = true
        motionEndTask?.cancel()
        motionEndTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            isMoving = false
        }
    }

    private static let thumbnailPixelSize: CGFloat = 520

    private func insert(_ item: ShelfItem, at index: Int = 0) {
        QuickLookPreviewPresenter.dismiss()
        makeRoom(keeping: items.indices.contains(index) ? items[index].id : nil)
        noteMotion()
        withAnimation(Self.slideIfAllowed) {
            items.insert(item, at: min(index, items.count))
            tuckReasons.removeAll()
        }
    }

    private func makeRoom(keeping keptID: ShelfItem.ID?) {
        let overflow = items.count + 1 - capacity
        guard overflow > 0 else { return }
        let removable = items.reversed().filter { $0.id != keptID }.prefix(overflow)
        for item in removable { dismiss(id: item.id) }
    }

    private func trimToCapacity() {
        let overflow = items.count - capacity
        guard overflow > 0 else { return }
        for item in items.suffix(overflow) { dismiss(id: item.id) }
    }

    private func update(_ id: ShelfItem.ID, _ change: (inout ShelfItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func engage(_ id: ShelfItem.ID) {
        update(id) { $0.isEngaged = true }
        autoCloseTasks[id]?.cancel()
        autoCloseTasks[id] = nil
    }

    private func flash(_ flash: ShelfFlash, on id: ShelfItem.ID) {
        withAnimation(.morphQuickIfAllowed) { update(id) { $0.flash = flash } }
        flashTasks[id]?.cancel()
        flashTasks[id] = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.morphQuickIfAllowed) { update(id) { $0.flash = nil } }
            flashTasks[id] = nil
        }
    }

    private func cancelTasks(for id: ShelfItem.ID) {
        autoCloseTasks.removeValue(forKey: id)?.cancel()
        flashTasks.removeValue(forKey: id)?.cancel()
        compressionTasks.removeValue(forKey: id)?.cancel()
    }

    private func scheduleAutoClose(id: ShelfItem.ID, after delay: Duration? = nil) {
        let seconds = UpshotPreferences.previewAutoCloseSeconds
        guard seconds > 0 else { return }
        autoCloseTasks[id]?.cancel()
        autoCloseTasks[id] = Task {
            try? await Task.sleep(for: delay ?? .seconds(seconds))
            guard !Task.isCancelled else { return }
            autoCloseIfIdle(id: id)
        }
    }

    private func autoCloseIfIdle(id: ShelfItem.ID) {
        guard let item = item(id: id), !item.isEngaged else { return }
        let isBusy = hoveredID == id
            || draggingID == id
            || item.activity != nil
            || CloudUploader.shared.uploadingItems.contains(id)
            || QuickLookPreviewPresenter.isShown
        if isBusy {
            scheduleAutoClose(id: id, after: .seconds(2))
        } else {
            performAutoClose(id: id)
        }
    }

    private func performAutoClose(id: ShelfItem.ID) {
        guard let item = item(id: id) else { return }
        let action = UpshotPreferences.previewAutoCloseAction
        autoCloseTasks[id] = nil
        engage(id)
        NSLog("Quick Access auto-close item=%@ action=%@ outcome=started", id.uuidString, action.rawValue)

        Task {
            let succeeded: Bool
            switch action {
            case .close:
                succeeded = true
            case .copyAndClose:
                switch item.kind {
                case .image: succeeded = copyImageToClipboard(item.url)
                case .video: succeeded = await copyVideoToClipboard(item.url, itemID: id)
                }
            case .saveAndClose:
                if let savedURL = item.savedURL, FileManager.default.fileExists(atPath: savedURL.path) {
                    succeeded = true
                } else {
                    let savedURL: URL?
                    switch item.kind {
                    case .image: savedURL = saveToDefaultLocation(from: item.url)
                    case .video: savedURL = await saveVideoToDefaultLocation(from: item.url, itemID: id)
                    }
                    update(id) { $0.savedURL = savedURL }
                    succeeded = savedURL != nil
                }
            }

            guard succeeded else {
                flash(.actionFailed(message: action == .saveAndClose ? "Save Failed" : "Copy Failed"), on: id)
                NSLog("Quick Access auto-close item=%@ action=%@ outcome=failed card=retained", id.uuidString, action.rawValue)
                return
            }
            dismiss(id: id)
            NSLog("Quick Access auto-close item=%@ action=%@ outcome=succeeded card=closed", id.uuidString, action.rawValue)
        }
    }

    private func loadVideoThumbnail(for id: ShelfItem.ID, from url: URL) {
        Task {
            guard let thumbnail = await VideoPreviewImageLoader.thumbnail(at: url, maxPixelSize: Self.thumbnailPixelSize) else { return }
            update(id) { $0.thumbnail = thumbnail }
        }
    }

    private func insertCompressed(_ result: ScreenshotCompressionResult, beside sourceID: ShelfItem.ID) {
        guard let thumbnail = ScreenshotImageLoader.downsampledImage(at: result.outputURL, maxPixelSize: Self.thumbnailPixelSize) else { return }
        let item = ShelfItem(url: result.outputURL, thumbnail: thumbnail)
        insert(item, at: items.firstIndex { $0.id == sourceID } ?? 0)
        flash(.compressed(summary: result.displaySummary), on: item.id)
    }

    private func runAfterCaptureActions(type: AfterCaptureType, url: URL, itemID: ShelfItem.ID?) {
        if AfterCaptureActions.isEnabled(.copy, for: type) {
            switch type {
            case .screenshot: _ = copyImageToClipboard(url)
            case .recording: Task { _ = await copyVideoToClipboard(url, itemID: itemID) }
            }
        }

        if AfterCaptureActions.isEnabled(.upload, for: type) {
            if let itemID {
                upload(id: itemID)
            } else {
                uploadUnattended(url)
            }
        }

        switch type {
        case .screenshot:
            if AfterCaptureActions.isEnabled(.annotate, for: type) {
                if let itemID { engage(itemID) }
                CaptureShelfPresenter.shared.onAnnotate?(url)
            }
            if AfterCaptureActions.isEnabled(.pin, for: type) {
                PinnedScreenshotPresenter.shared.pin(url: url)
            }
        case .recording:
            if AfterCaptureActions.isEnabled(.openVideoEditor, for: type) {
                if let itemID { engage(itemID) }
                CaptureShelfPresenter.shared.onEditVideo?(url)
            }
        }
    }

    private func uploadUnattended(_ url: URL) {
        guard CloudUploader.shared.isConfigured else { return }
        Task {
            do {
                let result = try await CloudUploader.shared.upload(
                    itemID: UUID(),
                    fileURL: url,
                    socialEnabled: CloudUploadPreferences.lastSocialEnabled
                )
                copyString(result.url)
                ScreenshotHistoryStore.shared.setCloudURL(for: url, cloudURL: result.url)
            } catch {
                print("Auto cloud upload failed: \(error)")
            }
        }
    }

    private func republish(_ id: ShelfItem.ID) {
        guard let item = item(id: id) else { return }
        if let savedURL = item.savedURL {
            do {
                try ScreenshotFileActions.replaceExistingExport(from: item.url, at: savedURL)
            } catch {
                print("Failed to update saved screenshot: \(error)")
            }
        } else if UpshotPreferences.autoSave {
            let savedURL = saveToDefaultLocation(from: item.url)
            update(id) { $0.savedURL = savedURL }
        }

        if UpshotPreferences.autoCopy {
            _ = copyImageToClipboard(item.url)
        }
    }

    private func presentSaveFailure(_ error: Error, id: ShelfItem.ID) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The screenshot could not be saved"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Choose Another Location…")
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(id: id, choosingLocation: true)
        case .alertSecondButtonReturn: save(id: id)
        default: break
        }
    }

    private func copyString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func copyImageToClipboard(_ url: URL) -> Bool {
        do {
            try ScreenshotFileActions.copyImageToClipboard(from: url)
            return true
        } catch {
            print("Failed to copy screenshot: \(error)")
            return false
        }
    }

    private func saveToDefaultLocation(from url: URL) -> URL? {
        do {
            return try ScreenshotFileActions.saveToDefaultLocation(from: url)
        } catch {
            print("Failed to auto save: \(error)")
            return nil
        }
    }

    private func deleteFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to delete capture: \(error)")
        }
    }


    private func copyVideoToClipboard(_ url: URL, itemID: ShelfItem.ID?) async -> Bool {
        do {
            let deliverable = try await prepareDeliverable(from: url, itemID: itemID)
            try VideoFileActions.copyToClipboard(from: deliverable)
            return true
        } catch {
            presentRecordingFailure("The recording could not be copied", error: error)
            return false
        }
    }

    private func saveVideoToDefaultLocation(from url: URL, itemID: ShelfItem.ID?) async -> URL? {
        do {
            let deliverable = try await prepareDeliverable(from: url, itemID: itemID)
            return try await VideoFileActions.saveToDefaultLocation(from: deliverable)
        } catch {
            presentRecordingFailure("The recording could not be saved", error: error)
            return nil
        }
    }

    private func prepareDeliverable(from url: URL, itemID: ShelfItem.ID?) async throws -> URL {
        guard RecordingDeliverable.needsRender(for: url), let itemID else {
            return try await RecordingDeliverable.resolve(for: url)
        }
        engage(itemID)
        update(itemID) { $0.activity = .preparing }
        defer { update(itemID) { $0.activity = nil } }
        return try await RecordingDeliverable.resolve(for: url)
    }

    private func presentRecordingFailure(_ message: String, error: Error) {
        FailureAlert.present(message: message, error: error, detail: "Your recording is safe in its project.")
    }
}
