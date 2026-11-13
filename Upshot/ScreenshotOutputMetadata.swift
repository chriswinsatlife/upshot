import Foundation
import ImageIO

nonisolated enum ScreenshotOutputMetadata {
    static let backgroundPresetDescription = "Upshot automatic background preset applied"

    static func hasAppliedBackgroundPreset(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        return hasAppliedBackgroundPreset(properties: properties)
    }

    static func hasAppliedBackgroundPreset(properties: [CFString: Any]) -> Bool {
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        return png?[kCGImagePropertyPNGDescription] as? String == backgroundPresetDescription
    }
}
