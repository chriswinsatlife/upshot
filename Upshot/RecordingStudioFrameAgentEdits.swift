import Foundation

enum RecordingStudioFrameAgentEdits {
    static func normalize(_ patch: JSONValue, document: JSONValue) throws -> JSONValue {
        guard let stylePatch = patch["style"]?.objectValue else { return document }
        let fields = Set(stylePatch.keys).intersection([
            "backgroundBlur", "paddingSides", "authoredGradient", "shadow", "usesLayeredShadow"
        ])
        guard !fields.isEmpty else { return document }
        do {
            var result = document
            if let raw = stylePatch["backgroundBlur"], raw != .null {
                guard let value = raw.doubleValue, value.isFinite, (0...8).contains(value) else {
                    throw AgentToolError.message("style.backgroundBlur must be from 0 through 8 pixels.")
                }
            }
            if let raw = stylePatch["paddingSides"], raw != .null {
                guard let stored = result["style"]?["paddingSides"] else {
                    throw AgentToolError.message("style.paddingSides requires top, bottom, left, right, and linked.")
                }
                let sides = try stored.decode(as: RecordingStudioPadding.self)
                guard [sides.top, sides.bottom, sides.left, sides.right].allSatisfy(\.isFinite),
                      sides.top >= 0, sides.bottom >= 0, sides.left >= 0, sides.right >= 0,
                      sides.left <= 100, sides.right <= 100,
                      sides.top <= (sides.linked ? 100 : 250), sides.bottom <= (sides.linked ? 100 : 250) else {
                    throw AgentToolError.message("Padding sides require 0 through 100 percent; unlinked top and bottom allow 250 percent.")
                }
                result = result.merging(["style": ["paddingSides": try JSONValue(encoding: sides.normalized)]])
            }
            if let raw = stylePatch["authoredGradient"], raw != .null {
                guard let stored = result["style"]?["authoredGradient"] else {
                    throw AgentToolError.message("style.authoredGradient requires angle and colors.")
                }
                let gradient = try stored.decode(as: RecordingStudioGradient.self)
                guard gradient.isValid, (0...360).contains(gradient.angle) else {
                    throw AgentToolError.message("Custom gradients require an angle from 0 through 360 and 2 through 5 six-digit hexadecimal RGB colors.")
                }
                let normalized = gradient.normalized
                result = result.merging(["style": [
                    "authoredGradient": try JSONValue(encoding: normalized),
                    "background": try JSONValue(encoding: StoredBackgroundStyle.gradient(StoredGradient(normalized.backgroundGradient)))
                ]])
            }
            if stylePatch["shadow"] != nil {
                guard let value = stylePatch["shadow"]?.doubleValue, value.isFinite, (0...1).contains(value) else {
                    throw AgentToolError.message("style.shadow must be from 0 through 1.")
                }
                if stylePatch["usesLayeredShadow"] == nil {
                    result = result.merging(["style": ["usesLayeredShadow": true]])
                }
            }
            AppLog.event("recording", "agent_studio_frame_validated", fields: ["fields": fields.sorted().joined(separator: ",")])
            return result
        } catch {
            AppLog.event("recording", "agent_studio_frame_update_failed", fields: ["error": AppLog.error(error)])
            throw error
        }
    }
}
