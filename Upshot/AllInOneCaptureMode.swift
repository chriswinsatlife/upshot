import Foundation

enum AllInOneCaptureMode: String, CaseIterable, Identifiable {
    case area
    case window
    case fullscreen
    case previousArea
    case element
    case scrolling
    case recording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: "Area"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        case .previousArea: "Previous Area"
        case .element: "Element"
        case .scrolling: "Scrolling"
        case .recording: "Recording"
        }
    }

    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .fullscreen: "display"
        case .previousArea: "arrow.counterclockwise"
        case .element: "cursorarrow.click"
        case .scrolling: "scroll"
        case .recording: "record.circle"
        }
    }

    var shortcut: String {
        switch self {
        case .area: "a"
        case .window: "w"
        case .fullscreen: "f"
        case .previousArea: "p"
        case .element: "e"
        case .scrolling: "s"
        case .recording: "r"
        }
    }
}
