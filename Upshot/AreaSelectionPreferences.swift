import AppKit

extension UpshotPreferences {
    static let areaSelectionCrosshairKey = "areaSelectionCrosshair"
    static let areaSelectionMagnifierKey = "areaSelectionMagnifier"

    static var areaSelectionCrosshair: Bool {
        get { UserDefaults.standard.object(forKey: areaSelectionCrosshairKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: areaSelectionCrosshairKey) }
    }

    static var areaSelectionMagnifier: Bool {
        get { UserDefaults.standard.object(forKey: areaSelectionMagnifierKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: areaSelectionMagnifierKey) }
    }

    static let areaSelectionFreezeScreenKey = "areaSelectionFreezeScreen"

    static var areaSelectionFreezeScreen: Bool {
        get { UserDefaults.standard.object(forKey: areaSelectionFreezeScreenKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: areaSelectionFreezeScreenKey) }
    }
}
