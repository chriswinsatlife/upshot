import Foundation

extension AgentTools {
    static func normalizedCursorPatch(_ patch: JSONValue, currentEffect: RecordingClickEffect) throws -> JSONValue {
        var patch = patch
        if let effectValue = patch["clickEffect"], effectValue != .null {
            guard let raw = effectValue.stringValue, let effect = RecordingClickEffect(rawValue: raw) else {
                AppLog.event("recording", "agent_click_effect_failed", fields: ["field": "clickEffect"])
                throw AgentToolError.message("clickEffect must be impact, none, spotlight, ripple, echo, or burst.")
            }
            if effect != currentEffect, effect != .none, effect != .impact, patch["clickEffectColor"] == nil {
                patch = patch.merging(["clickEffectColor": .string(RecordingClickEffectSettings.defaultColor)])
            }
        }
        if let colorValue = patch["clickEffectColor"], colorValue != .null {
            guard let raw = colorValue.stringValue, let color = RecordingClickEffectSettings.normalizedColor(raw) else {
                AppLog.event("recording", "agent_click_effect_failed", fields: ["field": "clickEffectColor"])
                throw AgentToolError.message("clickEffectColor must be #RGB or #RRGGBB.")
            }
            patch = patch.merging(["clickEffectColor": .string(color)])
        }
        for (key, range) in [
            ("clickEffectScale", 0.5...2.0),
            ("clickEffectOpacity", 0.0...1.0),
            ("clickEffectDuration", 0.12...1.2)
        ] {
            try validateCursorNumber(patch[key], field: key, range: range)
        }
        for (key, range) in [
            ("cursorSmoothing", 0.0...2.0),
            ("cursorSpringStiffnessMultiplier", 0.25...3.0),
            ("cursorSpringDampingMultiplier", 0.25...3.0),
            ("cursorSpringMassMultiplier", 0.25...3.0)
        ] {
            try validateCursorNumber(patch["style"]?[key], field: "style.\(key)", range: range)
        }
        return patch
    }

    private static func validateCursorNumber(_ raw: JSONValue?, field: String, range: ClosedRange<Double>) throws {
        guard let raw, raw != .null else { return }
        guard let value = raw.doubleValue, value.isFinite, range.contains(value) else {
            AppLog.event("recording", "agent_cursor_setting_failed", fields: ["field": field])
            throw AgentToolError.message("\(field) must be a number from \(range.lowerBound) to \(range.upperBound).")
        }
    }
}
