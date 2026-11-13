import AppKit

enum AreaSelectionMemory {
    static func displayLayout(intersecting rect: CGRect? = nil) -> [String] {
        NSScreen.screens.compactMap { screen in
            guard rect.map({ screen.frame.intersects($0) }) ?? true, let id = ActiveDisplayResolver.displayID(for: screen) else { return nil }
            return "\(id):\(screen.frame.minX),\(screen.frame.minY),\(screen.frame.width),\(screen.frame.height)"
        }.sorted()
    }

    static var previousScreenshotRect: CGRect? {
        guard !UpshotPreferences.areaSelectionLastScreenshotDisplays.isEmpty, UpshotPreferences.areaSelectionLastScreenshotDisplays.allSatisfy(displayLayout().contains) else { return nil }
        return UpshotPreferences.areaSelectionLastScreenshotRect
    }

    static var lastSelectionRect: CGRect? {
        guard !UpshotPreferences.allInOneLastSelectionDisplays.isEmpty, UpshotPreferences.allInOneLastSelectionDisplays.allSatisfy(displayLayout().contains) else { return nil }
        return UpshotPreferences.allInOneLastSelectionRect
    }

    static func rememberSelection(mode: AllInOneCaptureMode, rect: CGRect) {
        UpshotPreferences.allInOneLastMode = mode
        if mode != .recording {
            UpshotPreferences.allInOneLastSelectionRect = rect
            UpshotPreferences.allInOneLastSelectionDisplays = displayLayout(intersecting: rect)
        }
        NSLog("All-In-One selection remembered: mode=%@ x=%.1f y=%.1f width=%.1f height=%.1f", mode.rawValue, rect.minX, rect.minY, rect.width, rect.height)
    }

    static func rememberScreenshot(rect: CGRect) {
        UpshotPreferences.areaSelectionLastScreenshotRect = rect
        UpshotPreferences.areaSelectionLastScreenshotDisplays = displayLayout(intersecting: rect)
        NSLog("Previous screenshot area remembered: x=%.1f y=%.1f width=%.1f height=%.1f", rect.minX, rect.minY, rect.width, rect.height)
    }
}
