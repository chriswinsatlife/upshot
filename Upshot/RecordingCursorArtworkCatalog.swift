import AppKit
import CoreGraphics
import Foundation

nonisolated enum RecordingCursorPose: String, CaseIterable, Sendable {
    case arrow
    case text
    case pointer
    case crosshair
    case openHand = "open-hand"
    case closedHand = "closed-hand"
    case resizeEW = "resize-ew"
    case resizeNS = "resize-ns"
    case notAllowed = "not-allowed"
}

nonisolated enum RecordingCursorShadowMetrics {
    static let offsetX: CGFloat = 0
    static let offsetY: CGFloat = 2
    static let blurRadius: CGFloat = 3
    static let opacity: CGFloat = 0.35
    static let padding: CGFloat = 12
}

@MainActor
enum RecordingCursorArtworkCatalog {
    private struct Entry {
        let anchorX: Double
        let anchorY: Double
        let aspectRatio: Double
        let hasBakedShadow: Bool
    }

    private static var cache: [String: PointerArtwork] = [:]
    private static var failures: Set<String> = []

    static func artwork(
        style: RecordingCursorStyle,
        pose: RecordingCursorPose = .arrow,
        inverted: Bool = false
    ) -> PointerArtwork? {
        guard style.usesArtworkCatalog else { return nil }
        let resolvedStyle = resolvedStyle(style, inverted: inverted)
        let resolvedPose = resolvedPose(pose, style: resolvedStyle)
        let key = "\(resolvedStyle.rawValue)/\(resolvedPose.rawValue)"
        if var cached = cache[key] {
            cached.leans = pose == .arrow && !style.replacesEveryCursor
            return cached
        }
        guard !failures.contains(key) else { return nil }
        guard let entry = entries[key] else {
            failures.insert(key)
            AppLog.event("recording", "cursor_artwork_load_failed", fields: [
                "style": resolvedStyle.rawValue,
                "pose": resolvedPose.rawValue,
                "reason": "missing_metadata"
            ])
            return nil
        }
        let imageName = "RecordingCursor-\(resolvedStyle.rawValue)-\(resolvedPose.rawValue)"
        guard let image = NSImage(named: NSImage.Name(imageName)),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            failures.insert(key)
            AppLog.event("recording", "cursor_artwork_load_failed", fields: [
                "style": resolvedStyle.rawValue,
                "pose": resolvedPose.rawValue,
                "reason": "image_decode"
            ])
            return nil
        }
        let height = 16 * Double(resolvedStyle.visibleBodySizeMultiplier)
        let width = height * entry.aspectRatio
        let artwork = PointerArtwork(
            artworkID: "recordly:\(key)",
            imageData: data,
            anchorPoint: PointerArtwork.Point(x: entry.anchorX * width, y: entry.anchorY * height),
            referenceSize: PointerArtwork.Size(width: width, height: height),
            leans: pose == .arrow && !style.replacesEveryCursor
        )
        cache[key] = artwork
        AppLog.event("recording", "cursor_artwork_loaded", fields: [
            "style": resolvedStyle.rawValue,
            "pose": resolvedPose.rawValue,
            "pixel_width": String(cgImage.width),
            "pixel_height": String(cgImage.height),
            "has_baked_shadow": String(entry.hasBakedShadow)
        ])
        return artwork
    }

    static func previewArtwork(
        style: RecordingCursorStyle,
        pointing: Bool = false,
        inverted: Bool = false
    ) -> PointerArtwork? {
        if style.usesArtworkCatalog {
            return artwork(style: style, pose: pointing ? .pointer : .arrow, inverted: inverted)
        }
        if let shape = style.shape, shape.isCircle {
            return shape.artwork
        }
        if pointing {
            return PointerShape.hand.artwork(inverted: inverted && style.shape != nil)
        }
        return style.shape?.artwork(inverted: inverted) ?? PointerArtworkCapture.defaultArtwork()
    }

    private static func resolvedStyle(_ style: RecordingCursorStyle, inverted: Bool) -> RecordingCursorStyle {
        if inverted && style == .tahoe { return .tahoeInverted }
        if inverted && style == .tahoeInverted { return .tahoe }
        return style
    }

    private static func resolvedPose(_ pose: RecordingCursorPose, style: RecordingCursorStyle) -> RecordingCursorPose {
        if style.replacesEveryCursor { return .arrow }
        if style == .boldOutline {
            return [.pointer, .openHand, .closedHand].contains(pose) ? .pointer : .arrow
        }
        return pose
    }

    private static let entries: [String: Entry] = [
        "macos/arrow": Entry(anchorX: 0.1070153846153847, anchorY: 0.03241379310344826, aspectRatio: 0.7004310344827587, hasBakedShadow: false),
        "macos/text": Entry(anchorX: 0.5, anchorY: 0.43248945147679324, aspectRatio: 0.5864978902953587, hasBakedShadow: false),
        "macos/pointer": Entry(anchorX: 0.29857142857142854, anchorY: 0.04276190476190478, aspectRatio: 0.95, hasBakedShadow: false),
        "macos/crosshair": Entry(anchorX: 0.5021413276231264, anchorY: 0.5010706638115632, aspectRatio: 1, hasBakedShadow: false),
        "macos/open-hand": Entry(anchorX: 0.4915458937198068, anchorY: 0.44819277108433736, aspectRatio: 0.9975903614457832, hasBakedShadow: false),
        "macos/closed-hand": Entry(anchorX: 0.5190735694822888, anchorY: 0.4690265486725664, aspectRatio: 1.0825958702064897, hasBakedShadow: false),
        "macos/resize-ew": Entry(anchorX: 0.49761336515513127, anchorY: 0.4350453172205438, aspectRatio: 1.2658610271903323, hasBakedShadow: false),
        "macos/resize-ns": Entry(anchorX: 0.5180180180180181, anchorY: 0.4486873508353222, aspectRatio: 0.7947494033412887, hasBakedShadow: false),
        "macos/not-allowed": Entry(anchorX: 0.05271784232365145, anchorY: 0, aspectRatio: 0.6566757493188011, hasBakedShadow: false),
        "tahoe/arrow": Entry(anchorX: 0.14, anchorY: 0.06, aspectRatio: 0.6450939457202505, hasBakedShadow: true),
        "tahoe-inverted/arrow": Entry(anchorX: 0.14, anchorY: 0.06, aspectRatio: 0.6450939457202505, hasBakedShadow: true),
        "tahoe/text": Entry(anchorX: 0.5, anchorY: 0.44, aspectRatio: 0.4577777777777778, hasBakedShadow: true),
        "tahoe-inverted/text": Entry(anchorX: 0.5, anchorY: 0.44, aspectRatio: 0.4577777777777778, hasBakedShadow: true),
        "tahoe/pointer": Entry(anchorX: 0.3018867924528302, anchorY: 0.05128205128205128, aspectRatio: 0.8493589743589743, hasBakedShadow: true),
        "tahoe-inverted/pointer": Entry(anchorX: 0.3018867924528302, anchorY: 0.05128205128205128, aspectRatio: 0.8493589743589743, hasBakedShadow: true),
        "tahoe/crosshair": Entry(anchorX: 0.5021413276231264, anchorY: 0.5010706638115632, aspectRatio: 1, hasBakedShadow: false),
        "tahoe-inverted/crosshair": Entry(anchorX: 0.5021413276231264, anchorY: 0.5010706638115632, aspectRatio: 1, hasBakedShadow: false),
        "tahoe/open-hand": Entry(anchorX: 0.5283018867924528, anchorY: 0.498371335504886, aspectRatio: 0.8631921824104235, hasBakedShadow: true),
        "tahoe-inverted/open-hand": Entry(anchorX: 0.5283018867924528, anchorY: 0.498371335504886, aspectRatio: 0.8631921824104235, hasBakedShadow: true),
        "tahoe/closed-hand": Entry(anchorX: 0.4652173913043478, anchorY: 0.3080357142857143, aspectRatio: 1.0267857142857142, hasBakedShadow: true),
        "tahoe-inverted/closed-hand": Entry(anchorX: 0.4652173913043478, anchorY: 0.3080357142857143, aspectRatio: 1.0267857142857142, hasBakedShadow: true),
        "tahoe/resize-ew": Entry(anchorX: 0.5, anchorY: 0.43829787234042555, aspectRatio: 2.127659574468085, hasBakedShadow: true),
        "tahoe-inverted/resize-ew": Entry(anchorX: 0.5, anchorY: 0.43829787234042555, aspectRatio: 2.127659574468085, hasBakedShadow: true),
        "tahoe/resize-ns": Entry(anchorX: 0.5, anchorY: 0.49, aspectRatio: 0.4511661807580175, hasBakedShadow: true),
        "tahoe-inverted/resize-ns": Entry(anchorX: 0.5, anchorY: 0.49, aspectRatio: 0.4511661807580175, hasBakedShadow: true),
        "tahoe/not-allowed": Entry(anchorX: 0.05271784232365145, anchorY: 0, aspectRatio: 0.6566757493188011, hasBakedShadow: true),
        "tahoe-inverted/not-allowed": Entry(anchorX: 0.05271784232365145, anchorY: 0, aspectRatio: 0.6566757493188011, hasBakedShadow: true),
        "windows11/arrow": Entry(anchorX: 0, anchorY: 0, aspectRatio: 1, hasBakedShadow: false),
        "windows11/text": Entry(anchorX: 0.5, anchorY: 0.5, aspectRatio: 1, hasBakedShadow: false),
        "windows11/pointer": Entry(anchorX: 0.1875, anchorY: 0, aspectRatio: 1, hasBakedShadow: false),
        "windows11/crosshair": Entry(anchorX: 0.5, anchorY: 0.5, aspectRatio: 1, hasBakedShadow: false),
        "windows11/open-hand": Entry(anchorX: 0.5, anchorY: 0.5, aspectRatio: 1, hasBakedShadow: false),
        "windows11/closed-hand": Entry(anchorX: 0.5, anchorY: 0.5, aspectRatio: 1, hasBakedShadow: false),
        "windows11/resize-ew": Entry(anchorX: 0.34375, anchorY: 0.125, aspectRatio: 1, hasBakedShadow: false),
        "windows11/resize-ns": Entry(anchorX: 0.125, anchorY: 0.34375, aspectRatio: 1, hasBakedShadow: false),
        "windows11/not-allowed": Entry(anchorX: 0.25, anchorY: 0.25, aspectRatio: 1, hasBakedShadow: false),
        "breezex/arrow": Entry(anchorX: 0.07550935431533302, anchorY: 0.0070216674238084914, aspectRatio: 0.6878172588832487, hasBakedShadow: true),
        "breezex/text": Entry(anchorX: 0.500036028246145, anchorY: 0.49506234670159627, aspectRatio: 0.3564356435643564, hasBakedShadow: true),
        "breezex/pointer": Entry(anchorX: 0.4382308553124647, anchorY: 0.00681665252625728, aspectRatio: 0.949874686716792, hasBakedShadow: true),
        "breezex/crosshair": Entry(anchorX: 0.4974160992217899, anchorY: 0.49609371031483984, aspectRatio: 1.0026109660574412, hasBakedShadow: true),
        "breezex/open-hand": Entry(anchorX: 0.5748305750992666, anchorY: 0.2819061391074367, aspectRatio: 0.9559902200488998, hasBakedShadow: true),
        "breezex/closed-hand": Entry(anchorX: 0.5269779507133594, anchorY: 0.1712991462918869, aspectRatio: 0.9850746268656716, hasBakedShadow: true),
        "breezex/resize-ew": Entry(anchorX: 0.4990213890816653, anchorY: 0.44397324356227863, aspectRatio: 2.803370786516854, hasBakedShadow: true),
        "breezex/resize-ns": Entry(anchorX: 0.49144193787814033, anchorY: 0.4771913267476851, aspectRatio: 0.34393638170974156, hasBakedShadow: true),
        "breezex/not-allowed": Entry(anchorX: 0.060901889938854904, anchorY: 0.0070216674238084914, aspectRatio: 0.8527918781725888, hasBakedShadow: true),
        "pixel-hand/arrow": Entry(anchorX: 0.35200000000000004, anchorY: 0.13, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/text": Entry(anchorX: 0.5, anchorY: 0.4000000000000001, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/pointer": Entry(anchorX: 0.35200000000000004, anchorY: 0.13, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/crosshair": Entry(anchorX: 0.5, anchorY: 0.4040000000000001, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/open-hand": Entry(anchorX: 0.38000000000000006, anchorY: 0.18000000000000002, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/closed-hand": Entry(anchorX: 0.38999999999999996, anchorY: 0.33, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/resize-ew": Entry(anchorX: 0.5, anchorY: 0.428, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/resize-ns": Entry(anchorX: 0.5, anchorY: 0.428, aspectRatio: 1, hasBakedShadow: true),
        "pixel-hand/not-allowed": Entry(anchorX: 0.5, anchorY: 0.34800000000000003, aspectRatio: 1, hasBakedShadow: true),
        "bold-outline/arrow": Entry(anchorX: 0.0625, anchorY: 0.04878048780487805, aspectRatio: 0.78125, hasBakedShadow: false),
        "bold-outline/pointer": Entry(anchorX: 0.14984776744186046, anchorY: 0.05516619753086419, aspectRatio: 1.0625, hasBakedShadow: false),
        "dot/arrow": Entry(anchorX: 0.5, anchorY: 0.5, aspectRatio: 1, hasBakedShadow: true),
        "figma/arrow": Entry(anchorX: 0.10126582278481013, anchorY: 0.050808314087759814, aspectRatio: 0.9122401847575058, hasBakedShadow: true)
    ]
}

nonisolated extension PointerArtwork {
    var cursorCatalogStyle: RecordingCursorStyle? {
        guard artworkID.hasPrefix("recordly:"),
              let style = artworkID.dropFirst("recordly:".count).split(separator: "/").first else {
            return nil
        }
        return RecordingCursorStyle(rawValue: String(style))
    }

    var usesNearestNeighborSampling: Bool {
        cursorCatalogStyle?.usesNearestNeighborSampling == true
    }

    var needsCursorShadow: Bool {
        guard let style = cursorCatalogStyle else { return false }
        switch style {
        case .macos, .windows11, .boldOutline: return true
        case .tahoe, .tahoeInverted: return artworkID.hasSuffix("/crosshair")
        default: return false
        }
    }
}
