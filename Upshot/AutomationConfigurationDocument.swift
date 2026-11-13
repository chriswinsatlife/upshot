import Foundation

nonisolated struct AutomationConfigurationDocument {
    var preferences: [String: JSONValue] = [:]
    var shortcuts: [String: String] = [:]

    init() {}

    init(text: String) throws {
        var section = ""
        var sections: Set<String> = []
        var keys: Set<String> = []
        for (offset, original) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = Self.removingComment(original).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                guard ["[preferences]", "[shortcuts]"].contains(line), sections.insert(line).inserted else {
                    throw AutomationError.message("Configuration line \(lineNumber): unknown or repeated table.")
                }
                section = String(line.dropFirst().dropLast())
                continue
            }
            guard !section.isEmpty, let separator = Self.assignmentIndex(in: line) else {
                throw AutomationError.message("Configuration line \(lineNumber): expected a key and value in a table.")
            }
            let rawKey = line[..<separator].trimmingCharacters(in: .whitespaces)
            let key: String
            if rawKey.hasPrefix("\"") || rawKey.hasPrefix("'") {
                guard case .string(let decoded) = try Self.scalar(rawKey, line: lineNumber) else {
                    throw AutomationError.message("Configuration line \(lineNumber): invalid quoted key.")
                }
                key = decoded
            } else {
                guard !rawKey.isEmpty, rawKey.utf8.allSatisfy({ byte in
                    (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || byte == 45
                }) else { throw AutomationError.message("Configuration line \(lineNumber): quote keys containing punctuation.") }
                key = rawKey
            }
            guard keys.insert("\(section).\(key)").inserted else { throw AutomationError.message("Configuration line \(lineNumber): duplicate key \(key).") }
            let value = try Self.scalar(line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces), line: lineNumber)
            if section == "preferences" {
                preferences[key] = value
            } else {
                guard case .string(let binding) = value else { throw AutomationError.message("Configuration line \(lineNumber): shortcut bindings must be strings.") }
                shortcuts[key] = binding
            }
        }
    }

    func encoded() throws -> String {
        var lines = ["[preferences]"]
        for key in preferences.keys.sorted() {
            lines.append("\(try Self.encodedScalar(.string(key))) = \(try Self.encodedScalar(preferences[key]!))")
        }
        lines += ["", "[shortcuts]"]
        for route in shortcuts.keys.sorted() {
            lines.append("\(try Self.encodedScalar(.string(route))) = \(try Self.encodedScalar(.string(shortcuts[route]!)))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func encodedScalar(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func scalar(_ text: String, line: Int) throws -> JSONValue {
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 {
            let value = String(text.dropFirst().dropLast())
            guard !value.contains("'") else { throw AutomationError.message("Configuration line \(line): invalid literal string.") }
            return .string(value)
        }
        if let value = try? JSONValue.decoder.decode(JSONValue.self, from: Data(text.utf8)) {
            switch value {
            case .string, .bool: return value
            case .number(let number) where number.isFinite: return value
            case .array(let values) where values.allSatisfy({ value in
                switch value {
                case .string: true
                case .number(let number): number.isFinite
                default: false
                }
            }): return value
            default: break
            }
        }
        throw AutomationError.message("Configuration line \(line): expected a quoted string, Boolean, finite decimal number, or one-line array of strings or numbers.")
    }

    private static func removingComment(_ text: String) -> String {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if let current = quote {
                if character == current { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" {
                return String(text[..<index])
            }
        }
        return text
    }

    private static func assignmentIndex(in text: String) -> String.Index? {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if let current = quote {
                if character == current { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "=" { return index }
        }
        return nil
    }
}
