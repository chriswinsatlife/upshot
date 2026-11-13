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

enum QuickAccessSwipeAction: String, CaseIterable, Identifiable {
    case none
    case tuck
    case copy
    case save
    case annotate
    case pin
    case view
    case upload
    case compress
    case close
    case delete

    var id: String { rawValue }

    var cardAction: OverlayCardAction? {
        OverlayCardAction(rawValue: rawValue)
    }

    var title: String {
        switch self {
        case .none: "Do Nothing"
        case .tuck: "Tuck Shelf"
        case .annotate: "Edit"
        case .close: "Close"
        default: cardAction?.label() ?? rawValue
        }
    }
}

extension UpshotPreferences {
    static let previewOverlaySizeKey = "previewOverlaySize"
    static let previewAutoCloseActionKey = "previewAutoCloseAction"
    static let previewCloseAfterUploadingKey = "previewCloseAfterUploading"
    static let previewSwipeTowardEdgeActionKey = "previewSwipeTowardEdgeAction"
    static let previewSwipeAwayFromEdgeActionKey = "previewSwipeAwayFromEdgeAction"
    static let pinnedScreenshotRoundedCornersKey = "pinnedScreenshotRoundedCorners"
    static let pinnedScreenshotShadowKey = "pinnedScreenshotShadow"
    static let pinnedScreenshotBorderKey = "pinnedScreenshotBorder"

    static var previewOverlaySize: QuickAccessOverlaySize {
        QuickAccessOverlaySize(rawValue: UserDefaults.standard.string(forKey: previewOverlaySizeKey) ?? "") ?? .small
    }

    static var previewAutoCloseAction: QuickAccessAutoCloseAction {
        QuickAccessAutoCloseAction(rawValue: UserDefaults.standard.string(forKey: previewAutoCloseActionKey) ?? "") ?? .close
    }

    static var previewCloseAfterUploading: Bool {
        UserDefaults.standard.bool(forKey: previewCloseAfterUploadingKey)
    }

    static var previewSwipeTowardEdgeAction: QuickAccessSwipeAction {
        QuickAccessSwipeAction(rawValue: UserDefaults.standard.string(forKey: previewSwipeTowardEdgeActionKey) ?? "") ?? .tuck
    }

    static var previewSwipeAwayFromEdgeAction: QuickAccessSwipeAction {
        QuickAccessSwipeAction(rawValue: UserDefaults.standard.string(forKey: previewSwipeAwayFromEdgeActionKey) ?? "") ?? .none
    }

    static var pinnedScreenshotRoundedCorners: Bool {
        UserDefaults.standard.object(forKey: pinnedScreenshotRoundedCornersKey) as? Bool ?? true
    }

    static var pinnedScreenshotShadow: Bool {
        UserDefaults.standard.object(forKey: pinnedScreenshotShadowKey) as? Bool ?? true
    }

    static var pinnedScreenshotBorder: Bool {
        UserDefaults.standard.object(forKey: pinnedScreenshotBorderKey) as? Bool ?? true
    }
}
