import AppKit

struct LiveStateKeyStroke: Equatable {
    static let returnKeyCode: UInt16 = 36
    static let escapeKeyCode: UInt16 = 53

    let keyCode: UInt16
    let characters: String
    let charactersIgnoringModifiers: String
    let modifiers: NSEvent.ModifierFlags

    private static func functionCharacter(_ value: Int) -> String {
        UnicodeScalar(UInt16(value)).map { String(Character($0)) } ?? ""
    }

    private static let functionKeys: [String: (UInt16, String)] = [
        "return": (36, "\r"), "escape": (53, "\u{1b}"), "tab": (48, "\t"), "delete": (51, "\u{7f}"), "space": (49, " "),
        "up": (126, functionCharacter(NSUpArrowFunctionKey)), "down": (125, functionCharacter(NSDownArrowFunctionKey)),
        "left": (123, functionCharacter(NSLeftArrowFunctionKey)), "right": (124, functionCharacter(NSRightArrowFunctionKey)),
    ]

    private static let shiftedBases: [Character: Character] = Dictionary(uniqueKeysWithValues: zip("!@#$%^&*()_+{}|:\"<>?~", "1234567890-=[]\\;',./`"))
    private static let shiftedCharacters = Set("!@#$%^&*()_+{}|:\"<>?~ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static let characterKeyCodes: [Character: UInt16] = {
        let unshifted: [(Character, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9), ("b", 11), ("q", 12),
            ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23),
            ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33), ("i", 34),
            ("p", 35), ("l", 37), ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43), ("/", 44), ("n", 45), ("m", 46),
            (".", 47), (" ", 49), ("`", 50),
        ]
        var codes = Dictionary(uniqueKeysWithValues: unshifted)
        for (shifted, base) in shiftedBases { codes[shifted] = codes[base] }
        for letter in "abcdefghijklmnopqrstuvwxyz" { codes[Character(letter.uppercased())] = codes[letter] }
        return codes
    }()

    static func modifierFlags(_ modifiers: [LiveStateModifier]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.command)
            case .shift: flags.insert(.shift)
            case .option: flags.insert(.option)
            case .control: flags.insert(.control)
            }
        }
        return flags
    }

    static func named(_ name: String, modifiers: [LiveStateModifier]) -> LiveStateKeyStroke? {
        var flags = modifierFlags(modifiers)
        if let (code, characters) = functionKeys[name] {
            if ["up", "down", "left", "right"].contains(name) { flags.formUnion([.function, .numericPad]) }
            return LiveStateKeyStroke(keyCode: code, characters: characters, charactersIgnoringModifiers: characters, modifiers: flags)
        }
        guard name.count == 1, let character = name.first else { return nil }
        return typed(character, modifiers: flags)
    }

    static func typed(_ character: Character, modifiers: NSEvent.ModifierFlags = []) -> LiveStateKeyStroke {
        var flags = modifiers
        if shiftedCharacters.contains(character) { flags.insert(.shift) }
        let base = shiftedBases[character] ?? Character(String(character).lowercased())
        let characters = flags.contains(.shift) && !shiftedCharacters.contains(character) ? String(character).uppercased() : String(character)
        return LiveStateKeyStroke(keyCode: characterKeyCodes[character] ?? characterKeyCodes[base] ?? 0, characters: characters,
                                  charactersIgnoringModifiers: String(base), modifiers: flags)
    }
}
