import Foundation

enum AllInOneCaptureMode: String, CaseIterable, Identifiable {
    case area
    case fullscreen
    case window
    case scrolling
    case timer
    case text
    case recording
    case previousArea
    case element

    static let toolbarCaptureModes: [AllInOneCaptureMode] = [.area, .fullscreen, .window, .scrolling, .timer]

    var id: String { rawValue }

    var isCaptureAction: Bool { self == .timer || self == .text }

    var title: String {
        switch self {
        case .area: "Area"
        case .fullscreen: "Fullscreen"
        case .window: "Window"
        case .scrolling: "Scrolling"
        case .timer: "Timer"
        case .text: "OCR"
        case .recording: "Recording"
        case .previousArea: "Previous Area"
        case .element: "Element"
        }
    }

    var symbol: String {
        switch self {
        case .area: "viewfinder"
        case .fullscreen: "display"
        case .window: "macwindow"
        case .scrolling: "arrow.down.to.line.compact"
        case .timer: "timer"
        case .text: "textformat"
        case .recording: "video"
        case .previousArea: "arrow.counterclockwise"
        case .element: "cursorarrow.click"
        }
    }

    var shortcut: String {
        switch self {
        case .area: "a"
        case .fullscreen: "f"
        case .window: "w"
        case .scrolling: "s"
        case .timer: "t"
        case .text: "o"
        case .recording: "r"
        case .previousArea: "p"
        case .element: "e"
        }
    }

    var toolbarHelp: String { "\(title) (\(shortcut.uppercased()))" }
}
