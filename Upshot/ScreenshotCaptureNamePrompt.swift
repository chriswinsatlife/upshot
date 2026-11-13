import AppKit
import Foundation

enum ScreenshotCaptureNamePrompt {
    static func makeNameField(name: String) -> NSTextField {
        let field = NSTextField(string: name)
        field.frame = NSRect(x: 0, y: 0, width: 228, height: 22)
        field.placeholderString = "Screenshot name"
        field.setAccessibilityLabel("Screenshot name")
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        return field
    }

    static func fileName(suggested: String, outputScale: CGFloat) -> String {
        guard UpshotPreferences.screenshotAskForName else { return suggested }
        let suggestedURL = URL(fileURLWithPath: suggested)
        let field = makeNameField(name: suggestedURL.deletingPathExtension().lastPathComponent)
        field.selectText(nil)
        AppLog.event("capture", "screenshot_output_capture_name_prompt_shown")
        guard AppAlerts.screenshotName.runModal(accessoryView: field, initialFirstResponder: field) == .save,
              !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLog.event("capture", "screenshot_output_generated_capture_name_retained")
            return suggested
        }
        let result = resolvedFileName(entered: field.stringValue, outputScale: outputScale)
        AppLog.event("capture", "screenshot_output_capture_name_accepted")
        return result
    }

    static func resolvedFileName(entered: String, outputScale: CGFloat) -> String {
        var stem = entered.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".png") { stem = String(stem.dropLast(4)) }
        return ScreenshotFileNaming.applyingRetinaSuffix(
            to: "\(ScreenshotFileNaming.sanitizedStem(stem)).png",
            outputScale: outputScale
        )
    }
}
