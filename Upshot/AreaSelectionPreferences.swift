import AppKit

extension UpshotPreferences {
    static let areaSelectionFreezeScreenKey = "areaSelectionFreezeScreen"

    static var areaSelectionFreezeScreen: Bool {
        get { UserDefaults.standard.object(forKey: areaSelectionFreezeScreenKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: areaSelectionFreezeScreenKey) }
    }
}
