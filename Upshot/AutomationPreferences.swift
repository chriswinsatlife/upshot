import Foundation

extension UpshotPreferences {
    static var configurationFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/upshot", isDirectory: true)
            .appendingPathComponent("config.toml")
    }
}

struct AutomationPreferenceDefinition {
    enum ArrayKind {
        case rectangle
        case strings
    }

    let defaultValue: JSONValue
    var range: ClosedRange<Double>?
    var integral = false
    var choices: [String]?
    var arrayKind: ArrayKind?
    var storesJSONData = false

    func validate(_ value: JSONValue, key: String) throws {
        let valid: Bool
        switch (defaultValue, value) {
        case (.bool, .bool): valid = true
        case (.string, .string(let text)): valid = choices?.contains(text) ?? true
        case (.number, .number(let number)):
            valid = number.isFinite && (range?.contains(number) ?? true) && (!integral || number.rounded() == number)
        case (.array, .array(let elements)):
            switch arrayKind {
            case .rectangle:
                let numbers = elements.compactMap { $0.doubleValue }
                valid = elements.isEmpty || (elements.count == 4 && numbers.count == 4 && numbers.allSatisfy(\.isFinite) && numbers[2] >= 1 && numbers[3] >= 1)
            case .strings: valid = elements.allSatisfy { $0.stringValue != nil }
            case nil: valid = false
            }
        default: valid = false
        }
        guard valid else { throw AutomationError.message("Invalid configuration value for \(key).") }
        if storesJSONData {
            guard let string = value.stringValue,
                  (try? JSONDecoder().decode(RecordingExportDeliveryOptions.self, from: Data(string.utf8))) != nil else {
                throw AutomationError.message("Invalid recording export defaults JSON.")
            }
        }
        if key == UpshotPreferences.screenshotFilenameTemplateKey,
           let template = value.stringValue, let error = ScreenshotFileNaming.templateError(template) {
            throw AutomationError.message(error)
        }
    }

    static var catalog: [String: Self] {
        var values: [String: Self] = [:]
        let booleans: [String: Bool] = [
            UpshotPreferences.autoSaveKey: false,
            UpshotPreferences.saveButtonUsesFolderKey: UpshotPreferences.autoSave,
            UpshotPreferences.autoCopyKey: false,
            UpshotPreferences.autoCompressKey: false,
            UpshotPreferences.playSoundsKey: true,
            UpshotPreferences.showMenuBarIconKey: true,
            UpshotPreferences.hideDockIconKey: false,
            UpshotPreferences.includeAppWindowsInCapturesKey: false,
            UpshotPreferences.captureWindowShadowKey: false,
            UpshotPreferences.previewCloseAfterDraggingKey: true,
            UpshotPreferences.lowResolutionEditorPreviewKey: true,
            UpshotPreferences.trimFullscreenMenuBarKey: true,
            UpshotPreferences.recordingSystemAudioKey: false,
            UpshotPreferences.recordingTeleprompterEnabledKey: false,
            UpshotPreferences.revealExportInFinderKey: true,
            UpshotPreferences.agentServerEnabledKey: true,
            UpshotPreferences.libraryAnalyzeCapturesKey: true,
            UpshotPreferences.librarySortExistingKey: false
        ]
        for (key, value) in booleans { values[key] = Self(defaultValue: .bool(value)) }
        for type in [AfterCaptureType.screenshot, .recording] {
            for action in AfterCaptureAction.actions(for: type) where values[action.storageKey(for: type)] == nil {
                values[action.storageKey(for: type)] = Self(defaultValue: .bool(action.defaultValue))
            }
        }
        values[UpshotPreferences.exportFormatKey] = Self(defaultValue: .string(UpshotPreferences.exportFormat.rawValue), choices: ScreenshotExportFormat.allCases.map(\.rawValue))
        values[UpshotPreferences.exportDirectoryPathKey] = Self(defaultValue: .string(UpshotPreferences.exportDirectory.path))
        values[UpshotPreferences.compressionQualityKey] = Self(defaultValue: 0.8, range: 0.1...1)
        values[UpshotPreferences.captureDelaySecondsKey] = Self(defaultValue: 0, range: 0...3600, integral: true)
        values[UpshotPreferences.recordingStartDelaySecondsKey] = Self(defaultValue: 0, range: 0...3600, integral: true)
        values[UpshotPreferences.previewAutoCloseSecondsKey] = Self(defaultValue: 0, range: 0...86400, integral: true)
        values[UpshotPreferences.shelfHandlePositionKey] = Self(defaultValue: 0.5, range: 0...1)
        values[UpshotPreferences.recordingTeleprompterLineCountKey] = Self(defaultValue: 3, range: 2...5, integral: true)
        values[UpshotPreferences.previewPositionKey] = Self(defaultValue: "right", choices: PreviewOverlayPosition.allCases.map(\.rawValue))
        values[UpshotPreferences.annotationStartingToolKey] = Self(defaultValue: .string(AnnotationTool.select.rawValue), choices: AnnotationTool.allCases.map(\.rawValue) + [UpshotPreferences.startingToolLastUsed])
        values[UpshotPreferences.recordingCameraDeviceIDKey] = Self(defaultValue: "")
        values[UpshotPreferences.recordingMicrophoneDeviceIDKey] = Self(defaultValue: "")
        values[UpshotPreferences.recordingTeleprompterScriptKey] = Self(defaultValue: "")
        values.merge(phaseTwoCatalog) { _, integrated in integrated }
        return values
    }
}
