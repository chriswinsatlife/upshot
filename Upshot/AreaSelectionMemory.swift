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
        AppLog.event("capture", "all_in_one_selection_remembered", fields: ["height": String(describing: rect.height), "mode": String(describing: mode.rawValue), "width": String(describing: rect.width), "x": String(describing: rect.minX), "y": String(describing: rect.minY)])
    }

    static func rememberScreenshot(rect: CGRect) {
        UpshotPreferences.areaSelectionLastScreenshotRect = rect
        UpshotPreferences.areaSelectionLastScreenshotDisplays = displayLayout(intersecting: rect)
        AppLog.event("capture", "previous_screenshot_area_remembered", fields: ["height": String(describing: rect.height), "width": String(describing: rect.width), "x": String(describing: rect.minX), "y": String(describing: rect.minY)])
    }
}
