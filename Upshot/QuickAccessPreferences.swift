import Foundation

enum QuickAccessOverlaySize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 1
        case .medium: 1.25
        case .large: 1.5
        }
    }
}

extension UpshotPreferences {
    static let previewOverlaySizeKey = "previewOverlaySize"

    static var previewOverlaySize: QuickAccessOverlaySize {
        QuickAccessOverlaySize(rawValue: UserDefaults.standard.string(forKey: previewOverlaySizeKey) ?? "") ?? .small
    }
}
