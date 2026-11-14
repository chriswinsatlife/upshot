enum LiveStateModifier: String, CaseIterable, Sendable {
    case command
    case shift
    case option
    case control
}

enum LiveStateCommand: Equatable, Sendable {
    case present(String)
    case click(x: Double, y: Double)
    case mouseDown(x: Double, y: Double)
    case mouseDragged(x: Double, y: Double)
    case mouseUp(x: Double, y: Double)
    case mouseMoved(x: Double, y: Double)
    case rightClick(x: Double, y: Double)
    case scroll(x: Double, y: Double, deltaX: Double, deltaY: Double)
    case key(name: String, modifiers: [LiveStateModifier])
    case type(String)
    case quit

    static let functionKeyNames: Set<String> = ["return", "escape", "tab", "delete", "space", "up", "down", "left", "right"]

    var word: String {
        switch self {
        case .present: "present"
        case .click: "click"
        case .mouseDown: "mouse_down"
        case .mouseDragged: "mouse_dragged"
        case .mouseUp: "mouse_up"
        case .mouseMoved: "mouse_moved"
        case .rightClick: "right_click"
        case .scroll: "scroll"
        case .key: "key"
        case .type: "type"
        case .quit: "quit"
        }
    }
}

enum LiveStateCommandParseResult: Equatable, Sendable {
    case command(LiveStateCommand)
    case rejectedPresent(reason: String)
    case ignored(reason: String)
    case empty
}

extension LiveStateCommand {
    static func parse(_ line: String) -> LiveStateCommandParseResult {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let word = parts.first else { return .empty }
        let arguments = Array(parts.dropFirst())
        func numbers(_ count: Int) -> [Double]? {
            guard arguments.count == count else { return nil }
            let values = arguments.compactMap(Double.init)
            return values.count == count && values.allSatisfy(\.isFinite) ? values : nil
        }
        func malformed() -> LiveStateCommandParseResult { .ignored(reason: "The \(word) command has malformed arguments.") }
        switch word {
        case "quit":
            return arguments.isEmpty ? .command(.quit) : malformed()
        case "present":
            guard arguments.count == 1 else { return .rejectedPresent(reason: "The present command needs exactly one state name.") }
            return .command(.present(arguments[0]))
        case "click", "mouse_down", "mouse_dragged", "mouse_up", "mouse_moved", "right_click":
            guard let point = numbers(2) else { return malformed() }
            switch word {
            case "click": return .command(.click(x: point[0], y: point[1]))
            case "mouse_down": return .command(.mouseDown(x: point[0], y: point[1]))
            case "mouse_dragged": return .command(.mouseDragged(x: point[0], y: point[1]))
            case "mouse_moved": return .command(.mouseMoved(x: point[0], y: point[1]))
            case "right_click": return .command(.rightClick(x: point[0], y: point[1]))
            default: return .command(.mouseUp(x: point[0], y: point[1]))
            }
        case "scroll":
            guard let values = numbers(4) else { return malformed() }
            return .command(.scroll(x: values[0], y: values[1], deltaX: values[2], deltaY: values[3]))
        case "key":
            guard arguments.count == 1 || arguments.count == 2 else { return malformed() }
            let name = arguments[0]
            guard functionKeyNames.contains(name) || name.count == 1 else {
                return .ignored(reason: "The key command names \(name.debugDescription), which is neither a named key nor one character.")
            }
            var modifiers: [LiveStateModifier] = []
            if arguments.count == 2 {
                for value in arguments[1].split(separator: "+", omittingEmptySubsequences: false).map(String.init) {
                    guard let modifier = LiveStateModifier(rawValue: value) else {
                        return .ignored(reason: "The key command names the unknown modifier \(value.debugDescription).")
                    }
                    if !modifiers.contains(modifier) { modifiers.append(modifier) }
                }
            }
            return .command(.key(name: name, modifiers: modifiers))
        case "type":
            let text = line.drop { $0 == " " }.dropFirst(word.count).dropFirst()
            guard !text.isEmpty else { return malformed() }
            return .command(.type(String(text)))
        default:
            return .ignored(reason: "The command \(word.debugDescription) is not part of the live state contract.")
        }
    }
}
