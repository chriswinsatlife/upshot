import AppKit
import Foundation

enum ScreenshotCaptureNamePrompt {
    static func fileName(suggested: String, outputScale: CGFloat) -> String {
        guard UpshotPreferences.screenshotAskForName else { return suggested }
        let suggestedURL = URL(fileURLWithPath: suggested)
        let field = NSTextField(string: suggestedURL.deletingPathExtension().lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 380, height: 24)
        field.placeholderString = "Screenshot name"
        field.setAccessibilityLabel("Screenshot name")
        let alert = NSAlert()
        alert.messageText = "Name Screenshot"
        alert.informativeText = "Enter the screenshot name. The PNG extension is added automatically."
        alert.accessoryView = field
        alert.addButton(withTitle: "Use Name")
        alert.addButton(withTitle: "Keep Generated Name")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        NSApplication.shared.activate(ignoringOtherApps: true)
        field.selectText(nil)
        AppLog.event("capture", "screenshot_output_capture_name_prompt_shown")
        guard alert.runModal() == .alertFirstButtonReturn,
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
