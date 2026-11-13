
enum AnnotationTool: String, CaseIterable, Identifiable, Codable {
    case select
    case rectangle
    case filledRectangle
    case ellipse
    case line
    case arrow
    case freehand
    case numberedCircle
    case text
    case highlight
    case highlighter
    case measure
    case pixelate
    case blur

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select:
            "Select"
        case .rectangle:
            "Rectangle"
        case .filledRectangle:
            "Solid rectangle"
        case .ellipse:
            "Circle"
        case .line:
            "Straight line"
        case .arrow:
            "Arrow"
        case .freehand:
            "Freehand"
        case .numberedCircle:
            "Numbered circle"
        case .pixelate:
            "Pixelate"
        case .blur:
            "Blur"
        case .text:
            "Text"
        case .highlight:
            "Spotlight"
        case .highlighter:
            "Highlighter"
        case .measure:
            "Measure"
        }
    }

    var systemImage: String {
        switch self {
        case .select:
            "hand.point.up.left"
        case .rectangle:
            "rectangle"
        case .filledRectangle:
            "square.fill"
        case .ellipse:
            "circle"
        case .line:
            "line.diagonal"
        case .arrow:
            "arrow.up.right"
        case .freehand:
            "scribble"
        case .numberedCircle:
            "1.circle.fill"
        case .pixelate:
            "app.background.dotted"
        case .blur:
            "drop.fill"
        case .text:
            "textformat"
        case .highlight:
            "square.dashed.inset.filled"
        case .highlighter:
            "highlighter"
        case .measure:
            "ruler"
        }
    }

    var helpText: String {
        if self == .highlighter {
            return "Highlight text with automatic snapping to recognized text"
        }
        if self == .highlight {
            return "Draw an area to keep visible; everything outside is dimmed"
        }
        return title
    }

    var isFilledShape: Bool {
        self == .filledRectangle
    }

    var usesEndpoints: Bool {
        self == .line || self == .arrow || self == .measure
    }

    var isRedactionTool: Bool {
        self == .pixelate || self == .blur
    }

    var supportsColorStyle: Bool {
        switch self {
        case .rectangle, .filledRectangle, .ellipse, .line, .arrow, .freehand, .numberedCircle, .text, .highlighter, .measure:
            true
        case .select, .pixelate, .blur, .highlight:
            false
        }
    }

    var supportsStrokeStyle: Bool {
        switch self {
        case .rectangle, .ellipse, .line, .arrow, .freehand, .measure:
            true
        case .select, .filledRectangle, .numberedCircle, .pixelate, .blur, .text, .highlight, .highlighter:
            false
        }
    }

    var supportsRedactionDensityStyle: Bool {
        isRedactionTool
    }

    var supportsAspectLock: Bool {
        switch self {
        case .rectangle, .filledRectangle, .ellipse, .highlight:
            true
        case .select, .line, .arrow, .freehand, .numberedCircle, .pixelate, .blur, .text, .highlighter, .measure:
            false
        }
    }

    var createsAnnotation: Bool {
        self != .select
    }
}
