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
        alert.window.initialFirstResponder = field
        NSApplication.shared.activate(ignoringOtherApps: true)
        field.selectText(nil)
        NSLog("Screenshot output: capture name prompt shown")
        guard alert.runModal() == .alertFirstButtonReturn,
              !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSLog("Screenshot output: generated capture name retained")
            return suggested
        }
        let result = resolvedFileName(entered: field.stringValue, outputScale: outputScale)
        NSLog("Screenshot output: capture name accepted")
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
