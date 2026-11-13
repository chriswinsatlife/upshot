import AppKit

enum AreaSelectionMemory {
    static func displayLayout() -> [String] {
        NSScreen.screens.compactMap { screen in
            guard let id = ActiveDisplayResolver.displayID(for: screen) else { return nil }
            return "\(id):\(screen.frame.minX),\(screen.frame.minY),\(screen.frame.width),\(screen.frame.height)"
        }.sorted()
    }

    static var previousScreenshotRect: CGRect? {
        guard UpshotPreferences.areaSelectionLastScreenshotDisplays == displayLayout() else { return nil }
        return UpshotPreferences.areaSelectionLastScreenshotRect
    }

    static func rememberScreenshot(rect: CGRect) {
        UpshotPreferences.areaSelectionLastScreenshotRect = rect
        UpshotPreferences.areaSelectionLastScreenshotDisplays = displayLayout()
        NSLog("Previous screenshot area remembered: x=%.1f y=%.1f width=%.1f height=%.1f", rect.minX, rect.minY, rect.width, rect.height)
    }
}
