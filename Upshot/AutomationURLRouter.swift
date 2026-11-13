import AppKit
import Foundation

nonisolated struct AutomationRequest {
    let route: String
    let parameters: [String: String]

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "upshot", components.user == nil,
              components.password == nil, components.port == nil, components.fragment == nil else {
            throw AutomationError.message("Invalid Upshot URL.")
        }
        route = ([components.host ?? ""] + components.path.split(separator: "/").map(String.init))
            .filter { !$0.isEmpty }.joined(separator: "/")
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value, values[item.name] == nil,
                  ["path", "output", "delay", "value"].contains(item.name) else {
                throw AutomationError.message("Unknown or duplicate URL parameter: \(item.name)")
            }
            values[item.name] = value
        }
        parameters = values
    }
}

enum AutomationURLRouter {
    static let confirmationRequiredActions: Set<CaptureHotkeyAction> = [
        .areaUpload, .editorShare, .recordingDiscard, .recordingRestart, .libraryTrash,
        .editorSave, .editorDone, .recordingEditorSave
    ]

    private static func confirm(_ action: CaptureHotkeyAction) -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow a link to run \u{201C}\(action.title)\u{201D}?"
        alert.informativeText = "Another app or a web page opened an Upshot link that uploads, shares, deletes, or saves changes."
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.buttons[0].keyEquivalent = ""
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func handle(_ url: URL) {
        Task { @MainActor in
            do {
                let request = try AutomationRequest(url: url)
                if let action = CaptureHotkeyAction.allCases.first(where: { $0.route == request.route }),
                   confirmationRequiredActions.contains(action), !confirm(action) {
                    AppLog.event("automation", "url_scheme_declined", fields: ["route": String(describing: request.route)])
                    return
                }
                _ = try await perform(route: request.route, parameters: request.parameters)
            } catch AutomationError.cancelled {
                AppLog.event("automation", "url_scheme_cancelled", fields: ["url": url.absoluteString])
            } catch {
                AppLog.event("automation", "url_scheme_failed", fields: ["error": AppLog.error(error)])
                let alert = NSAlert()
                alert.messageText = "Upshot could not perform the URL action"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    static func perform(route: String, parameters: [String: String]) async throws -> JSONValue {
        guard let action = CaptureHotkeyAction.allCases.first(where: { $0.route == route }) else {
            throw AutomationError.message("Unknown Upshot route: \(route)")
        }
        let allowed: Set<String>
        switch action {
        case .selfTimer: allowed = ["delay", "output"]
        case .editorCombineSideBySide, .editorCombineStacked: allowed = ["path"]
        case .editorWatermark: allowed = ["path", "value"]
        case .editorRedactionStyle, .editorColorAdjustments, .editorDrawingSmoothing,
             .editorObjectShadows, .editorExpandCanvas, .editorAlwaysOnTop: allowed = ["value"]
        default:
            allowed = action.route.hasPrefix("capture/") ? ["output"]
                : action == .editorOpen || action == .recordingEditorOpen || action.route.hasPrefix("editor/recording-") ? ["path"] : []
        }
        guard Set(parameters.keys).isSubset(of: allowed) else { throw AutomationError.message("This action does not accept the supplied parameters.") }
        if let output = parameters["output"] {
            guard output.hasPrefix("/"), !FileManager.default.fileExists(atPath: output),
                  FileManager.default.fileExists(atPath: URL(fileURLWithPath: output).deletingLastPathComponent().path) else {
                throw AutomationError.message("Output must be an absolute path to a new file in an existing directory.")
            }
            if action != .textCapture, URL(fileURLWithPath: output).pathExtension.lowercased() != "png" {
                throw AutomationError.message("Screenshot output requires a .png extension.")
            }
        }
        return try await AutomationActions.perform(action, parameters: parameters)
    }
}
