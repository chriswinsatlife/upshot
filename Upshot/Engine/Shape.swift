import AppKit
import Foundation

struct AnnoShapeID: Hashable, Codable {
    let raw: String
    init(_ raw: String = UUID().uuidString) { self.raw = raw }
}


enum DashStyle: String, CaseIterable, Codable {
    case draw
    case solid
    case dashed
    case dotted

    var label: String { rawValue.capitalized }
}

enum AnnoFillStyle: String, CaseIterable, Codable {
    case none
    case solid

    var label: String { self == .none ? "Outline" : "Solid" }
}

enum GeoKind: String, CaseIterable, Codable {
    case rectangle
    case ellipse

    var label: String { rawValue.capitalized }
}


struct GeoProps: Codable, Equatable {
    var isHighlighter: Bool?
    var geo: GeoKind = .rectangle
    var w: Double = 100
    var h: Double = 100
    var swatch: AnnotationSwatch = .red
    var strokeWidth: Double = 8
    var fill: AnnoFillStyle = .none
    var dash: DashStyle = .solid
    var cornerRadius: Double = 0
}

struct DrawProps: Codable, Equatable {
    var points: [Vec] = []
    var smoothing: Double?
    var isComplete = false
    var isPen = false
    var isClosed = false
    var swatch: AnnotationSwatch = .red
    var strokeWidth: Double = 8
}

enum Arrowhead: String, CaseIterable, Codable {
    case none
    case arrow
    case triangle
    case square
    case dot
    case diamond
    case inverted
    case bar
}

struct ArrowProps: Codable, Equatable {
    var isMeasurement: Bool?
    var start = Vec(0, 0)
    var end = Vec(100, 0)
    var bend: Double = 0
    var arrowheadStart: Arrowhead = .none
    var arrowheadEnd: Arrowhead = .arrow
    var swatch: AnnotationSwatch = .red
    var strokeWidth: Double = 8
    var dash: DashStyle = .solid
}

enum TextAlign: String, CaseIterable, Codable {
    case start
    case middle
    case end

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .start: .left
        case .middle: .center
        case .end: .right
        }
    }

    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .center: self = .middle
        case .right: self = .end
        default: self = .start
        }
    }
}

struct TextProps: Codable, Equatable, Hashable {
    var style: AnnotationTextStyle?
    var text: String = ""
    var swatch: AnnotationSwatch = .red
    var fontSize: Double = 48
    var fontFamily: AnnoFontFamily = .pro
    var isBold = true
    var isItalic = false
    var isUnderline = false
    var align: TextAlign = .start
    var w: Double = 16
    var autoSize = true
}

enum RedactionKind: String, CaseIterable, Codable {
    case blur
    case pixelate
    case box
    case disc
    case motionHorizontal
    case motionVertical
    case zoom
    case hexagonal

    var title: String {
        switch self {
        case .blur: "Gaussian"
        case .pixelate: "Pixelate"
        case .box: "Box"
        case .disc: "Disc"
        case .motionHorizontal: "Horizontal motion"
        case .motionVertical: "Vertical motion"
        case .zoom: "Zoom"
        case .hexagonal: "Hexagonal"
        }
    }
}

struct RedactionProps: Codable, Equatable {
    var kind: RedactionKind = .blur
    var w: Double = 100
    var h: Double = 100
    var density: Double = 0.55
}

struct HighlightProps: Codable, Equatable {
    var w: Double = 100
    var h: Double = 100
}

struct NumberedProps: Codable, Equatable {
    var value: Int = 1
    var diameter: Double = 64
    var swatch: AnnotationSwatch = .red
}


enum AnnoShapeKind: Codable, Equatable {
    case geo(GeoProps)
    case draw(DrawProps)
    case arrow(ArrowProps)
    case text(TextProps)
    case redaction(RedactionProps)
    case highlight(HighlightProps)
    case numbered(NumberedProps)
}

struct AnnoShape: Codable, Equatable, Identifiable {
    var id: AnnoShapeID
    var x: Double
    var y: Double
    var rotation: Double = 0
    var opacity: Double = 1
    var castsShadow: Bool?
    var kind: AnnoShapeKind

    init(
        id: AnnoShapeID = AnnoShapeID(),
        x: Double,
        y: Double,
        rotation: Double = 0,
        opacity: Double = 1,
        castsShadow: Bool? = nil,
        kind: AnnoShapeKind
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.rotation = rotation
        self.opacity = opacity
        self.castsShadow = castsShadow
        self.kind = kind
    }

    var pageTransform: Mat {
        Mat.compose(x: x, y: y, rotation: rotation)
    }

    var strokeWidth: Double {
        switch kind {
        case let .geo(p): p.strokeWidth
        case let .draw(p): p.strokeWidth
        case let .arrow(p): p.strokeWidth
        case .text, .redaction, .highlight, .numbered: 0
        }
    }

    var tool: AnnotationTool {
        switch kind {
        case let .geo(properties):
            if properties.isHighlighter == true { return .highlighter }
            switch (properties.geo, properties.fill) {
            case (.rectangle, .none): return .rectangle
            case (.rectangle, .solid): return .filledRectangle
            case (.ellipse, _): return .ellipse
            }
        case .draw: return .freehand
        case let .arrow(properties):
            if properties.isMeasurement == true { return .measure }
            return properties.arrowheadStart == .none && properties.arrowheadEnd == .none ? .line : .arrow
        case .text: return .text
        case let .redaction(properties): return properties.kind == .pixelate ? .pixelate : .blur
        case .highlight: return .highlight
        case .numbered: return .numberedCircle
        }
    }

    var swatch: AnnotationSwatch? {
        switch kind {
        case let .geo(p): p.swatch
        case let .draw(p): p.swatch
        case let .arrow(p): p.swatch
        case let .text(p): p.swatch
        case let .numbered(p): p.swatch
        case .redaction, .highlight: nil
        }
    }

    var isFilled: Bool {
        switch kind {
        case let .geo(p): p.fill != .none
        case let .draw(p): p.isClosed
        case .arrow: false
        case .text, .redaction, .highlight, .numbered: true
        }
    }

    var isArrow: Bool {
        if case .arrow = kind { return true }
        return false
    }

    var isText: Bool {
        if case .text = kind { return true }
        return false
    }

    var isRedaction: Bool {
        if case .redaction = kind { return true }
        return false
    }

    var isHighlight: Bool {
        if case .highlight = kind { return true }
        return false
    }

    var geoProps: GeoProps? {
        if case let .geo(p) = kind { return p }
        return nil
    }

    var drawProps: DrawProps? {
        if case let .draw(p) = kind { return p }
        return nil
    }

    var arrowProps: ArrowProps? {
        if case let .arrow(p) = kind { return p }
        return nil
    }

    var textProps: TextProps? {
        if case let .text(p) = kind { return p }
        return nil
    }

    var redactionProps: RedactionProps? {
        if case let .redaction(p) = kind { return p }
        return nil
    }

    var numberedProps: NumberedProps? {
        if case let .numbered(p) = kind { return p }
        return nil
    }
}


enum ArrowTerminal: String, Codable {
    case start
    case end
}

struct ArrowBinding: Codable, Equatable {
    var arrowId: AnnoShapeID
    var toId: AnnoShapeID
    var terminal: ArrowTerminal
    var normalizedAnchor: Vec
    var isPrecise: Bool
    var isExact: Bool
}


extension AnnotationSwatch: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, red, green, blue, alpha
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            red: try container.decode(CGFloat.self, forKey: .red),
            green: try container.decode(CGFloat.self, forKey: .green),
            blue: try container.decode(CGFloat.self, forKey: .blue),
            alpha: try container.decodeIfPresent(CGFloat.self, forKey: .alpha) ?? 1
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(alpha, forKey: .alpha)
    }
}
