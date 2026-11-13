import AppKit

extension UpshotPreferences {
    static let areaSelectionLastScreenshotRectKey = "areaSelectionLastScreenshotRect"
    static let areaSelectionLastScreenshotDisplaysKey = "areaSelectionLastScreenshotDisplays"

    static var areaSelectionLastScreenshotRect: CGRect? {
        get {
            guard let values = UserDefaults.standard.array(forKey: areaSelectionLastScreenshotRectKey) as? [Double],
                  values.count == 4, values.allSatisfy(\.isFinite), values[2] >= 1, values[3] >= 1 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: areaSelectionLastScreenshotRectKey)
                return
            }
            UserDefaults.standard.set([newValue.minX, newValue.minY, newValue.width, newValue.height], forKey: areaSelectionLastScreenshotRectKey)
        }
    }

    static var areaSelectionLastScreenshotDisplays: [String] {
        get { UserDefaults.standard.stringArray(forKey: areaSelectionLastScreenshotDisplaysKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: areaSelectionLastScreenshotDisplaysKey) }
    }

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
