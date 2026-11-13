import Foundation
import Observation

@Observable
final class AutomationConfiguration {
    static let shared = AutomationConfiguration()
    private(set) var errorMessage: String?
    private var timer: Timer?
    private var lastFileData: Data?
    private var lastSnapshot: String?
    private var rejectedFileData: Data?

    private init() {}

    func start() {
        guard timer == nil else { return }
        synchronize()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { Self.shared.synchronize() }
        }
    }

    func stop() {
        synchronize()
        timer?.invalidate()
        timer = nil
    }

    func reload() throws {
        let data = try Data(contentsOf: UpshotPreferences.configurationFileURL)
        try apply(data)
        lastFileData = data
        lastSnapshot = try snapshot().encoded()
        rejectedFileData = nil
        errorMessage = nil
        AppLog.event("automation", "configuration_loaded_preferences_and_shortcuts")
    }

    func synchronize() {
        guard !HotkeyManager.shared.isRecordingShortcut else { return }
        do {
            let url = UpshotPreferences.configurationFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                if data != lastFileData {
                    if data == rejectedFileData { return }
                    do { try reload() } catch {
                        rejectedFileData = data
                        throw error
                    }
                    return
                }
            }
            let encoded = try snapshot().encoded()
            guard encoded != lastSnapshot || !FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data(encoded.utf8)
            try data.write(to: url, options: .atomic)
            lastFileData = data
            lastSnapshot = encoded
            rejectedFileData = nil
            errorMessage = nil
            AppLog.event("automation", "configuration_saved_preferences_and_shortcuts")
        } catch {
            errorMessage = error.localizedDescription
            AppLog.event("automation", "configuration_rejected", fields: ["error": AppLog.error(error)])
        }
    }

    func snapshot() throws -> AutomationConfigurationDocument {
        var document = AutomationConfigurationDocument()
        for (key, definition) in AutomationPreferenceDefinition.catalog {
            if definition.storesJSONData, let data = UpshotStorage.defaults.data(forKey: key),
               let string = String(data: data, encoding: .utf8) {
                document.preferences[key] = .string(string)
            } else if let object = UpshotStorage.defaults.object(forKey: key),
               let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]),
               let value = try? JSONValue.decoder.decode(JSONValue.self, from: data) {
                document.preferences[key] = value
            } else { document.preferences[key] = definition.defaultValue }
            if [UpshotPreferences.exportDirectoryPathKey, UpshotPreferences.screenshotWindowWallpaperPathKey].contains(key),
               let path = document.preferences[key]?.stringValue {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                if path == home || path.hasPrefix(home + "/") {
                    document.preferences[key] = .string("~" + path.dropFirst(home.count))
                }
            }
        }
        for action in CaptureHotkeyAction.allCases {
            document.shortcuts[action.route] = Self.bindingString(CaptureHotkeyPreferences.shortcut(for: action))
        }
        return document
    }

    private func apply(_ data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw AutomationError.message("Configuration must contain UTF-8 text.") }
        let document = try AutomationConfigurationDocument(text: text)
        let definitions = AutomationPreferenceDefinition.catalog
        for (key, value) in document.preferences {
            guard let definition = definitions[key] else { throw AutomationError.message("Unknown configuration preference: \(key)") }
            try definition.validate(value, key: key)
        }
        var shortcuts = CaptureHotkeyPreferences.shortcuts()
        for (route, binding) in document.shortcuts {
            guard let action = CaptureHotkeyAction.allCases.first(where: { $0.route == route }) else {
                throw AutomationError.message("Unknown configuration shortcut: \(route)")
            }
            shortcuts[action] = try Self.shortcut(binding)
        }
        try HotkeyManager.shared.replaceShortcuts(shortcuts)
        for (key, value) in document.preferences {
            switch value {
            case .bool(let flag): UpshotStorage.defaults.set(flag, forKey: key)
            case .number(let number): UpshotStorage.defaults.set(number, forKey: key)
            case .string(let string):
                if definitions[key]?.storesJSONData == true {
                    UpshotStorage.defaults.set(Data(string.utf8), forKey: key)
                } else {
                    let value = [UpshotPreferences.exportDirectoryPathKey, UpshotPreferences.screenshotWindowWallpaperPathKey].contains(key)
                        ? (string as NSString).expandingTildeInPath : string
                    UpshotStorage.defaults.set(value, forKey: key)
                }
            case .array(let values):
                if definitions[key]?.arrayKind == .rectangle {
                    UpshotStorage.defaults.set(values.compactMap(\.doubleValue), forKey: key)
                } else {
                    UpshotStorage.defaults.set(values.compactMap(\.stringValue), forKey: key)
                }
            default: break
            }
        }
        AgentServer.shared.updateForPreference()
    }

    static func bindingString(_ shortcut: HotkeyShortcut?) -> String {
        guard let shortcut else { return "disabled" }
        var parts: [String] = []
        if shortcut.modifiers.contains(.control) { parts.append("control") }
        if shortcut.modifiers.contains(.option) { parts.append("option") }
        if shortcut.modifiers.contains(.shift) { parts.append("shift") }
        if shortcut.modifiers.contains(.command) { parts.append("command") }
        return (parts + [String(shortcut.keyCode)]).joined(separator: "+")
    }

    static func shortcut(_ binding: String) throws -> HotkeyShortcut? {
        if binding == "disabled" { return nil }
        let parts = binding.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let keyCode = Int(parts.last!), (0...127).contains(keyCode) else {
            throw AutomationError.message("Shortcut bindings require modifier names followed by a macOS key code, such as option+18.")
        }
        var modifiers: HotkeyShortcut.Modifiers = []
        for part in parts.dropLast() {
            let modifier: HotkeyShortcut.Modifiers
            switch part {
            case "command": modifier = .command
            case "option": modifier = .option
            case "control": modifier = .control
            case "shift": modifier = .shift
            default: throw AutomationError.message("Unknown shortcut modifier: \(part)")
            }
            guard !modifiers.contains(modifier) else { throw AutomationError.message("Duplicate shortcut modifier: \(part)") }
            modifiers.insert(modifier)
        }
        return HotkeyShortcut(modifiers: modifiers, keyCode: keyCode)
    }
}
