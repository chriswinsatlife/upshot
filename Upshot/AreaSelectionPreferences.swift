import AppKit

extension UpshotPreferences {
    static let allInOneLastModeKey = "allInOneLastMode"
    static let allInOneLastSelectionRectKey = "allInOneLastSelectionRect"
    static let allInOneLastSelectionDisplaysKey = "allInOneLastSelectionDisplays"

    static var allInOneLastMode: AllInOneCaptureMode {
        get { UpshotStorage.defaults.string(forKey: allInOneLastModeKey).flatMap(AllInOneCaptureMode.init(rawValue:)) ?? .area }
        set { UpshotStorage.defaults.set(newValue.rawValue, forKey: allInOneLastModeKey) }
    }

    static var allInOneLastSelectionRect: CGRect? {
        get {
            guard let values = UpshotStorage.defaults.array(forKey: allInOneLastSelectionRectKey) as? [Double],
                  values.count == 4, values.allSatisfy(\.isFinite), values[2] >= 1, values[3] >= 1 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        set {
            guard let newValue else {
                UpshotStorage.defaults.removeObject(forKey: allInOneLastSelectionRectKey)
                return
            }
            UpshotStorage.defaults.set([newValue.minX, newValue.minY, newValue.width, newValue.height], forKey: allInOneLastSelectionRectKey)
        }
    }

    static var allInOneLastSelectionDisplays: [String] {
        get { UpshotStorage.defaults.stringArray(forKey: allInOneLastSelectionDisplaysKey) ?? [] }
        set { UpshotStorage.defaults.set(newValue, forKey: allInOneLastSelectionDisplaysKey) }
    }

    static let areaSelectionLastScreenshotRectKey = "areaSelectionLastScreenshotRect"
    static let areaSelectionLastScreenshotDisplaysKey = "areaSelectionLastScreenshotDisplays"

    static var areaSelectionLastScreenshotRect: CGRect? {
        get {
            guard let values = UpshotStorage.defaults.array(forKey: areaSelectionLastScreenshotRectKey) as? [Double],
                  values.count == 4, values.allSatisfy(\.isFinite), values[2] >= 1, values[3] >= 1 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        set {
            guard let newValue else {
                UpshotStorage.defaults.removeObject(forKey: areaSelectionLastScreenshotRectKey)
                return
            }
            UpshotStorage.defaults.set([newValue.minX, newValue.minY, newValue.width, newValue.height], forKey: areaSelectionLastScreenshotRectKey)
        }
    }

    static var areaSelectionLastScreenshotDisplays: [String] {
        get { UpshotStorage.defaults.stringArray(forKey: areaSelectionLastScreenshotDisplaysKey) ?? [] }
        set { UpshotStorage.defaults.set(newValue, forKey: areaSelectionLastScreenshotDisplaysKey) }
    }

    static let areaSelectionCrosshairKey = "areaSelectionCrosshair"
    static let areaSelectionMagnifierKey = "areaSelectionMagnifier"

    static var areaSelectionCrosshair: Bool {
        get { UpshotStorage.defaults.object(forKey: areaSelectionCrosshairKey) as? Bool ?? false }
        set { UpshotStorage.defaults.set(newValue, forKey: areaSelectionCrosshairKey) }
    }

    static var areaSelectionMagnifier: Bool {
        get { UpshotStorage.defaults.object(forKey: areaSelectionMagnifierKey) as? Bool ?? true }
        set { UpshotStorage.defaults.set(newValue, forKey: areaSelectionMagnifierKey) }
    }

    static let areaSelectionFreezeScreenKey = "areaSelectionFreezeScreen"

    static var areaSelectionFreezeScreen: Bool {
        get { UpshotStorage.defaults.object(forKey: areaSelectionFreezeScreenKey) as? Bool ?? false }
        set { UpshotStorage.defaults.set(newValue, forKey: areaSelectionFreezeScreenKey) }
    }
}
