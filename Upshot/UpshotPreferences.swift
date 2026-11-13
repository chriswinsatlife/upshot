import AppKit
import ImageIO
import UniformTypeIdentifiers

enum UpshotPreferences {
    static let autoSaveKey = "autoSaveScreenshots"
    static let saveButtonUsesFolderKey = "saveButtonUsesConfiguredFolder"
    static let autoCopyKey = "autoCopyScreenshotsToClipboard"
    static let autoCompressKey = "autoCompressScreenshots"
    static let exportFormatKey = "exportFormat"
    static let compressionQualityKey = "compressionQuality"
    static let exportDirectoryPathKey = "exportDirectoryPath"
    static let fullscreenHotkeyKey = "captureHotkey.fullscreen"
    static let windowHotkeyKey = "captureHotkey.window"
    static let areaHotkeyKey = "captureHotkey.area"
    static let textCaptureHotkeyKey = "captureHotkey.textCapture"
    static let screenRecordingHotkeyKey = "captureHotkey.screenRecording"
    static let playSoundsKey = "playSounds"
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let hideDockIconKey = "hideDockIcon"
    static let includeAppWindowsInCapturesKey = "includeAppWindowsInCaptures"
    static let captureWindowShadowKey = "captureWindowShadow"
    static let captureDelaySecondsKey = "captureDelaySeconds"
    static let previewPositionKey = "previewPosition"
    static let previewAutoCloseSecondsKey = "previewAutoCloseSeconds"
    static let previewCloseAfterDraggingKey = "previewCloseAfterDragging"
    static let shelfHandlePositionKey = "captureShelfHandlePosition"
    static let overlayCardLayoutKey = "overlayCardLayout"
    static let lowResolutionEditorPreviewKey = "lowResolutionEditorPreview"
    static let annotationStartingToolKey = "annotationStartingTool"
    static let startingToolLastUsed = "lastUsed"
    static let trimFullscreenMenuBarKey = "trimFullscreenMenuBar"
    static let recordingCameraDeviceIDKey = "recordingCameraDeviceID"
    static let recordingMicrophoneDeviceIDKey = "recordingMicrophoneDeviceID"
    static let recordingSystemAudioKey = "recordingSystemAudio"
    static let recordingStartDelaySecondsKey = "recordingStartDelaySeconds"
    static let recordingTeleprompterEnabledKey = "recordingTeleprompterEnabled"
    static let recordingTeleprompterScriptKey = "recordingTeleprompterScript"
    static let recordingTeleprompterLineCountKey = "recordingTeleprompterLineCount"
    static let revealExportInFinderKey = "revealExportInFinder"
    static let agentServerEnabledKey = "agentServerEnabled"
    static let recordingAreaAspectKey = "recordingAreaAspect"
    static let recordingAreaLastSelectionKey = "recordingAreaLastSelection"

    private static let defaultCompressionQuality = 0.8

    static var autoSave: Bool {
        UpshotStorage.defaults.bool(forKey: autoSaveKey)
    }

    static var saveButtonUsesConfiguredFolder: Bool {
        if UpshotStorage.defaults.object(forKey: saveButtonUsesFolderKey) == nil {
            return autoSave
        }
        return UpshotStorage.defaults.bool(forKey: saveButtonUsesFolderKey)
    }

    static var autoCopy: Bool {
        UpshotStorage.defaults.bool(forKey: autoCopyKey)
    }

    static var autoCompress: Bool {
        UpshotStorage.defaults.bool(forKey: autoCompressKey)
    }

    static var exportFormat: ScreenshotExportFormat {
        if let rawValue = UpshotStorage.defaults.string(forKey: exportFormatKey),
           let format = ScreenshotExportFormat(rawValue: rawValue) {
            return format
        }

        return autoCompress ? .jpeg : .png
    }

    static var compressionQuality: Double {
        let value = UpshotStorage.defaults.object(forKey: compressionQualityKey) as? Double ?? defaultCompressionQuality
        return min(max(value, 0.1), 1)
    }

    static var exportDirectory: URL {
        if let path = UpshotStorage.defaults.string(forKey: exportDirectoryPathKey),
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return defaultExportDirectory
    }

    static var defaultExportDirectory: URL {
        let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        return (picturesDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures"))
            .appendingPathComponent("Upshot", isDirectory: true)
    }

    static var recordingCameraDeviceID: String {
        get { UpshotStorage.defaults.string(forKey: recordingCameraDeviceIDKey) ?? "" }
        set { UpshotStorage.defaults.set(newValue, forKey: recordingCameraDeviceIDKey) }
    }

    static var recordingMicrophoneDeviceID: String {
        get { UpshotStorage.defaults.string(forKey: recordingMicrophoneDeviceIDKey) ?? "" }
        set { UpshotStorage.defaults.set(newValue, forKey: recordingMicrophoneDeviceIDKey) }
    }

    static var recordingSystemAudio: Bool {
        get { UpshotStorage.defaults.bool(forKey: recordingSystemAudioKey) }
        set { UpshotStorage.defaults.set(newValue, forKey: recordingSystemAudioKey) }
    }

    static var recordingStartDelaySeconds: Int {
        max(0, UpshotStorage.defaults.integer(forKey: recordingStartDelaySecondsKey))
    }

    static var recordingAreaAspect: RecordingAreaAspect? {
        get {
            UpshotStorage.defaults.string(forKey: recordingAreaAspectKey)
                .flatMap(RecordingAreaAspect.init(storageValue:))
        }
        set { UpshotStorage.defaults.set(newValue?.storageValue ?? "", forKey: recordingAreaAspectKey) }
    }

    static var recordingAreaLastSelection: (displayID: CGDirectDisplayID, rect: CGRect)? {
        get {
            let parts = (UpshotStorage.defaults.string(forKey: recordingAreaLastSelectionKey) ?? "")
                .split(separator: ",")
                .compactMap { Double($0) }
            guard parts.count == 5, parts[3] > 0, parts[4] > 0 else { return nil }
            return (CGDirectDisplayID(parts[0]), CGRect(x: parts[1], y: parts[2], width: parts[3], height: parts[4]))
        }
        set {
            guard let newValue else {
                UpshotStorage.defaults.removeObject(forKey: recordingAreaLastSelectionKey)
                return
            }
            let rect = newValue.rect
            let value = [Double(newValue.displayID), rect.minX, rect.minY, rect.width, rect.height]
                .map { String($0) }
                .joined(separator: ",")
            UpshotStorage.defaults.set(value, forKey: recordingAreaLastSelectionKey)
        }
    }

    static var recordingTeleprompterEnabled: Bool {
        get { UpshotStorage.defaults.bool(forKey: recordingTeleprompterEnabledKey) }
        set { UpshotStorage.defaults.set(newValue, forKey: recordingTeleprompterEnabledKey) }
    }

    static var recordingTeleprompterScript: String {
        get { UpshotStorage.defaults.string(forKey: recordingTeleprompterScriptKey) ?? "" }
        set { UpshotStorage.defaults.set(newValue, forKey: recordingTeleprompterScriptKey) }
    }

    static let teleprompterLineCountRange = 2...5

    static var recordingTeleprompterLineCount: Int {
        get {
            let stored = UpshotStorage.defaults.integer(forKey: recordingTeleprompterLineCountKey)
            guard stored != 0 else { return 3 }
            return min(max(stored, teleprompterLineCountRange.lowerBound), teleprompterLineCountRange.upperBound)
        }
        set { UpshotStorage.defaults.set(newValue, forKey: recordingTeleprompterLineCountKey) }
    }

    static var playSounds: Bool {
        if UpshotStorage.defaults.object(forKey: playSoundsKey) == nil {
            return true
        }
        return UpshotStorage.defaults.bool(forKey: playSoundsKey)
    }

    static var showMenuBarIcon: Bool {
        if UpshotStorage.defaults.object(forKey: showMenuBarIconKey) == nil {
            return true
        }
        return UpshotStorage.defaults.bool(forKey: showMenuBarIconKey)
    }

    static var hideDockIcon: Bool {
        UpshotStorage.defaults.bool(forKey: hideDockIconKey)
    }

    static var includeAppWindowsInCaptures: Bool {
        UpshotStorage.defaults.bool(forKey: includeAppWindowsInCapturesKey)
    }

    static var captureWindowShadow: Bool {
        UpshotStorage.defaults.bool(forKey: captureWindowShadowKey)
    }

    static var captureDelaySeconds: Int {
        max(0, UpshotStorage.defaults.integer(forKey: captureDelaySecondsKey))
    }

    static var previewPosition: PreviewOverlayPosition {
        guard let raw = UpshotStorage.defaults.string(forKey: previewPositionKey),
              let position = PreviewOverlayPosition(rawValue: raw) else {
            return .right
        }
        return position
    }

    static var previewAutoCloseSeconds: Int {
        max(0, UpshotStorage.defaults.integer(forKey: previewAutoCloseSecondsKey))
    }

    static var previewCloseAfterDragging: Bool {
        if UpshotStorage.defaults.object(forKey: previewCloseAfterDraggingKey) == nil {
            return true
        }
        return UpshotStorage.defaults.bool(forKey: previewCloseAfterDraggingKey)
    }

    static var lowResolutionEditorPreview: Bool {
        if UpshotStorage.defaults.object(forKey: lowResolutionEditorPreviewKey) == nil {
            return true
        }
        return UpshotStorage.defaults.bool(forKey: lowResolutionEditorPreviewKey)
    }

    static var revealExportInFinder: Bool {
        if UpshotStorage.defaults.object(forKey: revealExportInFinderKey) == nil {
            return true
        }
        return UpshotStorage.defaults.bool(forKey: revealExportInFinderKey)
    }

    static var agentServerEnabled: Bool {
        if UpshotStorage.defaults.object(forKey: agentServerEnabledKey) == nil {
            return true
        }
        return UpshotStorage.defaults.bool(forKey: agentServerEnabledKey)
    }

    static var trimFullscreenMenuBar: Bool {
        if UpshotStorage.defaults.object(forKey: trimFullscreenMenuBarKey) == nil {
            return true
        }
        return UpshotStorage.defaults.bool(forKey: trimFullscreenMenuBarKey)
    }

    static var cloudWorkerURL: String {
        CloudCredentialStore.shared.workerURL
    }

    static var cloudUploadToken: String {
        CloudCredentialStore.shared.uploadToken
    }

    static var isCloudConfigured: Bool {
        CloudCredentialStore.shared.isConfigured
    }
}

enum PreviewOverlayPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Bottom left"
        case .right: "Bottom right"
        }
    }
}

enum ScreenshotExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png:
            "PNG"
        case .jpeg:
            "JPEG"
        case .heic:
            "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .png:
            "png"
        case .jpeg:
            "jpg"
        case .heic:
            "heic"
        }
    }

    var contentType: UTType {
        switch self {
        case .png:
            .png
        case .jpeg:
            .jpeg
        case .heic:
            .heic
        }
    }

    var usesLossyQuality: Bool {
        self != .png
    }
}

enum ScreenshotFileActions {
    static func copyImageToClipboard(from url: URL) throws {
        try ScreenshotClipboardService.copy(from: url)
    }

    static func copyPNGToClipboard(from url: URL) throws {
        try ScreenshotClipboardService.copy(from: url)
    }

    @discardableResult
    static func saveToDefaultLocation(from url: URL) throws -> URL {
        let destinationDirectory = UpshotPreferences.exportDirectory
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let destinationURL = uniqueDestinationURL(
            for: exportFileName(for: url),
            in: destinationDirectory
        )
        try save(from: url, to: destinationURL)
        return destinationURL
    }

    static func save(from sourceURL: URL, to destinationURL: URL) throws {
        if UpshotPreferences.exportFormat == .png {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try exportImage(from: sourceURL, to: destinationURL, contentType: UpshotPreferences.exportFormat.contentType)
        }
    }

    static func replaceExistingExport(from sourceURL: URL, at destinationURL: URL) throws {
        guard let destinationType = exportContentType(for: destinationURL) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".Upshot-\(UUID().uuidString)-\(destinationURL.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        if destinationType == .png, actualImageContentType(at: sourceURL) == .png {
            try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
        } else {
            try exportImage(from: sourceURL, to: stagingURL, contentType: destinationType)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        }
    }

    static func exportFileName(for sourceURL: URL) -> String {
        return sourceURL
            .deletingPathExtension()
            .appendingPathExtension(UpshotPreferences.exportFormat.fileExtension)
            .lastPathComponent
    }

    static var exportContentType: UTType {
        UpshotPreferences.exportFormat.contentType
    }

    private static func exportImage(from sourceURL: URL, to destinationURL: URL, contentType: UTType) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let options: [CFString: Any] = contentType == .png ? [:] : [
            kCGImageDestinationLossyCompressionQuality: UpshotPreferences.compressionQuality
        ]

        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func exportContentType(for url: URL) -> UTType? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .heic) { return .heic }
        return nil
    }

    private static func actualImageContentType(at url: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let identifier = CGImageSourceGetType(source) else {
            return nil
        }

        guard let type = UTType(identifier as String) else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .heic) { return .heic }
        return type
    }

    private static func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let originalURL = directory.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return originalURL
        }

        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let pathExtension = originalURL.pathExtension

        for index in 1...10_000 {
            let numberedName = "\(baseName) \(index)"
            let candidateURL = directory
                .appendingPathComponent(numberedName)
                .appendingPathExtension(pathExtension)

            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory
            .appendingPathComponent("\(baseName) \(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}

extension UpshotPreferences {
    static let libraryAnalyzeCapturesKey = "libraryAnalyzeCaptures"
    static let librarySortExistingKey = "librarySortExistingCaptures"
    static let librarySortOfferDismissedKey = "librarySortOfferDismissed"
    private static let libraryAutoSortSinceKey = "libraryAutoSortSince"

    static var libraryAnalyzeCaptures: Bool {
        UpshotStorage.defaults.object(forKey: libraryAnalyzeCapturesKey) as? Bool ?? true
    }

    static var librarySortExisting: Bool {
        UpshotStorage.defaults.bool(forKey: librarySortExistingKey)
    }

    static var libraryAutoSortSince: Date {
        let stored = UpshotStorage.defaults.double(forKey: libraryAutoSortSinceKey)
        if stored > 0 { return Date(timeIntervalSinceReferenceDate: stored) }
        let now = Date()
        UpshotStorage.defaults.set(now.timeIntervalSinceReferenceDate, forKey: libraryAutoSortSinceKey)
        return now
    }
}
