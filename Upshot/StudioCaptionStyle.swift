import CoreGraphics
import Foundation

nonisolated enum StudioCaptionPreset: String, Codable, Sendable, CaseIterable {
    case upshot
    case reveal
    case serif

    var title: String {
        switch self {
        case .upshot: "Upshot"
        case .reveal: "Reveal"
        case .serif: "Classic"
        }
    }
}

nonisolated enum StudioCaptionAnimation: String, Codable, Sendable, CaseIterable {
    case none
    case fade
    case rise
    case pop

    var title: String {
        switch self {
        case .none: "Off"
        case .fade: "Fade"
        case .rise: "Rise"
        case .pop: "Pop"
        }
    }
}

nonisolated struct SubtitleBarStyle: Codable, Sendable, Equatable {
    static let verticalRange: ClosedRange<Double> = 0.1...0.95
    static let fontScaleRange: ClosedRange<Double> = 0.6...1.8

    var verticalPosition: Double = 0.92
    var fontScale: Double = 1
    var highlightsSpokenWord = false
    var preset: StudioCaptionPreset = .upshot
    var fontSize: Double = 30
    var maximumRows = 1
    var bottomOffset: Double = 3
    var maximumWidth: Double = 62
    var boxRadius: Double = 8
    var backgroundOpacity: Double = 1
    var animation: StudioCaptionAnimation = .none
    var textColor = "#FFFFFF"
    var inactiveTextColor = "#FFFFFF"
    var revealsWords = true
    var highlightFill = "#FFFFFF29"
    var highlightTextColor = "#FFFFFF"

    init() {}

    init(preset: StudioCaptionPreset) {
        apply(preset)
    }

    mutating func apply(_ preset: StudioCaptionPreset) {
        self.preset = preset
        textColor = preset == .serif ? "#181818" : "#FFFFFF"
        inactiveTextColor = textColor
        highlightTextColor = textColor
        backgroundOpacity = 1
        boxRadius = 8
        animation = .none
        revealsWords = true
    }

    var clampedVerticalPosition: Double {
        Self.clamp(verticalPosition, to: Self.verticalRange, fallback: 0.92)
    }

    var clampedFontScale: Double {
        Self.clamp(fontScale, to: Self.fontScaleRange, fallback: 1)
    }

    var normalized: Self {
        var result = self
        result.verticalPosition = clampedVerticalPosition
        result.fontScale = clampedFontScale
        result.fontSize = Self.clamp(fontSize, to: 16...72, fallback: 30)
        result.maximumRows = min(4, max(1, maximumRows))
        result.bottomOffset = Self.clamp(bottomOffset, to: 0...30, fallback: 3)
        result.maximumWidth = Self.clamp(maximumWidth, to: 40...95, fallback: 62)
        result.boxRadius = Self.clamp(boxRadius, to: 0...40, fallback: 8)
        result.backgroundOpacity = Self.clamp(backgroundOpacity, to: 0...1, fallback: 1)
        result.textColor = StudioCaptionColor.validated(textColor) ?? "#FFFFFF"
        result.inactiveTextColor = StudioCaptionColor.validated(inactiveTextColor) ?? result.textColor
        result.highlightFill = StudioCaptionColor.validated(highlightFill) ?? "#FFFFFF29"
        result.highlightTextColor = StudioCaptionColor.validated(highlightTextColor) ?? result.textColor
        return result
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    private enum CodingKeys: String, CodingKey {
        case verticalPosition, fontScale, highlightsSpokenWord, preset, fontSize, maximumRows
        case bottomOffset, maximumWidth, boxRadius, backgroundOpacity, animation
        case textColor, inactiveTextColor, revealsWords, highlightFill, highlightTextColor
    }

    init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presetID = try container.decodeIfPresent(String.self, forKey: .preset)
        apply(presetID.flatMap(StudioCaptionPreset.init(rawValue:)) ?? (presetID == nil ? .upshot : .reveal))
        verticalPosition = try container.decodeIfPresent(Double.self, forKey: .verticalPosition) ?? verticalPosition
        fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? fontScale
        highlightsSpokenWord = try container.decodeIfPresent(Bool.self, forKey: .highlightsSpokenWord) ?? highlightsSpokenWord
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
        maximumRows = try container.decodeIfPresent(Int.self, forKey: .maximumRows) ?? maximumRows
        bottomOffset = try container.decodeIfPresent(Double.self, forKey: .bottomOffset) ?? bottomOffset
        maximumWidth = try container.decodeIfPresent(Double.self, forKey: .maximumWidth) ?? maximumWidth
        boxRadius = try container.decodeIfPresent(Double.self, forKey: .boxRadius) ?? boxRadius
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? backgroundOpacity
        animation = try container.decodeIfPresent(StudioCaptionAnimation.self, forKey: .animation) ?? animation
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor) ?? textColor
        inactiveTextColor = try container.decodeIfPresent(String.self, forKey: .inactiveTextColor) ?? inactiveTextColor
        revealsWords = try container.decodeIfPresent(Bool.self, forKey: .revealsWords) ?? revealsWords
        highlightFill = try container.decodeIfPresent(String.self, forKey: .highlightFill) ?? highlightFill
        highlightTextColor = try container.decodeIfPresent(String.self, forKey: .highlightTextColor) ?? highlightTextColor
        self = normalized
    }
}

nonisolated enum StudioCaptionColor {
    static func validated(_ value: String) -> String? {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard (hex.count == 6 || hex.count == 8), UInt64(hex, radix: 16) != nil else { return nil }
        return "#" + hex.uppercased()
    }

    static func color(_ value: String) -> CGColor {
        let hex = String((validated(value) ?? "#FFFFFF").dropFirst())
        let integer = UInt64(hex, radix: 16) ?? 0xFFFFFF
        let rgba = hex.count == 8 ? integer : (integer << 8) | 0xFF
        return CGColor(
            red: CGFloat((rgba >> 24) & 255) / 255,
            green: CGFloat((rgba >> 16) & 255) / 255,
            blue: CGFloat((rgba >> 8) & 255) / 255,
            alpha: CGFloat(rgba & 255) / 255
        )
    }
}
