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

enum QuickAccessAutoCloseAction: String, CaseIterable, Identifiable {
    case close
    case saveAndClose
    case copyAndClose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .close: "Close"
        case .saveAndClose: "Save and Close"
        case .copyAndClose: "Copy and Close"
        }
    }
}

extension UpshotPreferences {
    static let previewOverlaySizeKey = "previewOverlaySize"
    static let previewAutoCloseActionKey = "previewAutoCloseAction"

    static var previewOverlaySize: QuickAccessOverlaySize {
        QuickAccessOverlaySize(rawValue: UserDefaults.standard.string(forKey: previewOverlaySizeKey) ?? "") ?? .small
    }

    static var previewAutoCloseAction: QuickAccessAutoCloseAction {
        QuickAccessAutoCloseAction(rawValue: UserDefaults.standard.string(forKey: previewAutoCloseActionKey) ?? "") ?? .close
    }
}
