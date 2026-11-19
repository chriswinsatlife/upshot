import Foundation
import Yams

nonisolated struct AutomationConfigurationDocument {
    var preferences: [String: JSONValue] = [:]
    var shortcuts: [String: String] = [:]

    private static let resolver = Resolver.basic.appending(.bool).appending(.int).appending(.float).appending(.null)

    init() {}

    init(text: String) throws {
        let root: Node?
        do {
            root = try Yams.compose(yaml: text, Self.resolver)
        } catch let error as YamlError {
            throw AutomationError.message("Configuration is not valid YAML: \(error)")
        }
        guard let root else { return }
        guard let mapping = root.mapping else {
            throw AutomationError.message("Configuration line \(Self.line(of: root)): expected a mapping with preferences and shortcuts.")
        }
        for (keyNode, valueNode) in mapping {
            let section = try Self.key(keyNode)
            guard section == "preferences" || section == "shortcuts" else {
                throw AutomationError.message("Configuration line \(Self.line(of: keyNode)): unknown section \(section).")
            }
            if valueNode.scalar != nil, Self.tagName(of: valueNode) == .null { continue }
            guard let entries = valueNode.mapping else {
                throw AutomationError.message("Configuration line \(Self.line(of: valueNode)): \(section) must be a mapping of keys to values.")
            }
            for (entryKeyNode, entryValueNode) in entries {
                let key = try Self.key(entryKeyNode)
                let value = try Self.value(entryValueNode)
                if section == "preferences" {
                    preferences[key] = value
                } else {
                    guard case .string(let binding) = value else {
                        throw AutomationError.message("Configuration line \(Self.line(of: entryValueNode)): shortcut bindings must be strings.")
                    }
                    shortcuts[key] = binding
                }
            }
        }
    }

    func encoded() throws -> String {
        let preferenceNodes = try preferences.keys.sorted().map { key in
            (Node.scalar(key.represented()), try Self.node(for: preferences[key]!))
        }
        let shortcutNodes = shortcuts.keys.sorted().map { route in
            (Node.scalar(route.represented()), Node.scalar(shortcuts[route]!.represented()))
        }
        let root = Node.mapping(Node.Mapping([
            (Node("preferences"), Node.mapping(Node.Mapping(preferenceNodes))),
            (Node("shortcuts"), Node.mapping(Node.Mapping(shortcutNodes)))
        ]))
        return try Yams.serialize(node: root, width: -1, allowUnicode: true)
    }

    private static func node(for value: JSONValue) throws -> Node {
        switch value {
        case .bool(let flag):
            return Node(flag ? "true" : "false", Yams.Tag(.bool))
        case .number(let number):
            return Node(try encodedNumber(number), Yams.Tag(number.rounded() == number ? .int : .float))
        case .string(let string):
            return .scalar(string.represented())
        case .array(let values):
            return .sequence(Node.Sequence(try values.map(node(for:)), Yams.Tag(.seq), .flow))
        case .null, .object:
            throw AutomationError.message("Configuration values must be strings, Booleans, numbers, or lists of strings or numbers.")
        }
    }

    private static func encodedNumber(_ number: Double) throws -> String {
        guard number.isFinite else { throw AutomationError.message("Configuration numbers must be finite.") }
        return String(decoding: try JSONEncoder().encode(number), as: UTF8.self)
    }

    private static func key(_ node: Node) throws -> String {
        guard case .scalar(let scalar) = node, !scalar.string.isEmpty else {
            throw AutomationError.message("Configuration line \(line(of: node)): keys must be non-empty strings.")
        }
        return scalar.string
    }

    private static func value(_ node: Node) throws -> JSONValue {
        switch node {
        case .scalar(let scalar):
            switch Self.tagName(of: node) {
            case .bool:
                if let flag = node.bool { return .bool(flag) }
            case .int:
                if let integer = node.int { return .number(Double(integer)) }
            case .float:
                if let number = node.float, number.isFinite { return .number(number) }
            case .str:
                return .string(scalar.string)
            default:
                break
            }
        case .sequence(let sequence):
            let values = try sequence.map(value)
            if values.allSatisfy({ if case .array = $0 { false } else { true } }) {
                return .array(values)
            }
        case .mapping, .alias:
            break
        }
        throw AutomationError.message("Configuration line \(line(of: node)): expected a string, Boolean, finite number, or list of strings or numbers.")
    }

    private static func tagName(of node: Node) -> Yams.Tag.Name {
        Yams.Tag.Name(rawValue: node.tag.rawValue)
    }

    private static func line(of node: Node) -> Int {
        node.mark?.line ?? 0
    }
}
