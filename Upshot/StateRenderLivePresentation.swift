import AppKit
import SwiftUI

enum StateRenderLivePresentation {
    private struct Request {
        let name: String
        let definition: StateRenderDefinition
        let appearance: String
        let scrollFrame: Int?
    }

    private struct Presented {
        let name: String
        let stage: StateRenderStage
        let window: NSWindow
    }

    private struct KeyStroke {
        let keyCode: UInt16
        let characters: String
        let charactersIgnoringModifiers: String
        let modifiers: NSEvent.ModifierFlags
    }

    private static var definitions: [String: StateRenderDefinition] = [:]
    private static var presented: Presented?
    private static var isolation: StateRenderIsolation?
    private static var activity: NSObjectProtocol?
    private static var safetyTimer: Timer?
    private static var isFinishing = false
    private static var isPresenting = false
    private static var queuedLines: [String] = []
    private static var isDispatchingMouseDown = false
    private static var pendingMouseDownAcknowledgement = false
    private static var isMouseDown = false
    private static var eventNumber = 0
    private static var displaySafety: StateRenderDisplaySafety?
    private static var displaySafetyChecks = 0

    static func run() -> Never {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let listing = UpshotStorage.isListingLiveStates
        guard listing ? arguments.count == 1 : arguments.count == 2 && !arguments[1].hasPrefix("--") else {
            FileHandle.standardError.write(Data(StateRenderer.usage.utf8))
            emit(["event": "live_state_failed", "reason": listing
                ? "The arguments must be --list-live-states with nothing after it."
                : "The arguments must be --present-live-state followed by one frame name."])
            exit(2)
        }
        let app = NSApplication.shared
        guard app.setActivationPolicy(.prohibited) else {
            emit(["event": "live_state_failed", "reason": "The activation policy could not be set to prohibited."])
            exit(1)
        }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Present a live render state")
        Task { @MainActor in
            do {
                if listing {
                    try await list()
                    finish()
                } else {
                    try await start(arguments[1])
                }
            } catch {
                fail(error.localizedDescription)
            }
        }
        app.run()
        exit(1)
    }

    private static func loadCatalog() async throws -> [StateRenderDefinition] {
        isolation = try StateRenderIsolation()
        let catalog = try await StateRenderer.loadDefinitions()
        definitions = Dictionary(uniqueKeysWithValues: catalog.map { ($0.name, $0) })
        return catalog
    }

    private static func list() async throws {
        let catalog = try await loadCatalog()
        var states: [[String: Any]] = []
        var unsupported: [[String: Any]] = []
        for definition in catalog {
            for appearance in ["light", "dark"] {
                let name = definition.name + "-" + appearance
                if let reason = unsupportedReason(definition) {
                    unsupported.append(["name": name, "reason": reason])
                } else {
                    states.append(["name": name, "baseState": definition.name, "appearance": appearance,
                                   "sourceFile": definition.sourceFile, "sourceLine": definition.line])
                }
            }
        }
        AppLog.event("rendering", "live_states", fields: ["states": String(describing: states.count), "unsupported": String(describing: unsupported.count)])
        emit(["event": "live_states", "states": states, "unsupported": unsupported])
    }

    static func unsupportedReason(_ definition: StateRenderDefinition) -> String? {
        switch definition.placement {
        case .window:
            return nil
        case .panel:
            return "The state \(definition.name) is a borderless panel with no titled window."
        case .display:
            return "The state \(definition.name) covers the display with no titled window."
        case .alert(nil):
            return "The state \(definition.name) is an alert window with no titled window."
        case .alert(let context?):
            return "The state \(definition.name) is an alert window over the \(context) window, so it needs two windows."
        case .popover(let context, _):
            return "The state \(definition.name) is a popover panel over the \(context) window, so it needs two windows."
        case .panelOverContext(let context, _):
            return "The state \(definition.name) is a panel around the \(context) window, so it needs two windows."
        case .panelOverDisplay:
            return "The state \(definition.name) is a panel over a display-sized backdrop with no titled window."
        }
    }

    private static func start(_ name: String) async throws {
        _ = try await loadCatalog()
        try await present(resolve(name))
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { checkSafety() }
        }
        Thread.detachNewThread { readCommands() }
    }

    private static func resolve(_ name: String) throws -> Request {
        let selection = StateRenderer.Selection(name)
        guard let appearance = selection.appearance else {
            throw StateRenderFailure(message: "The frame name \(name) has no -light or -dark appearance suffix.")
        }
        guard let definition = definitions[selection.state] else {
            throw StateRenderFailure(message: "The frame name \(name) names no state in the catalog.")
        }
        if let reason = unsupportedReason(definition) { throw StateRenderFailure(message: reason) }
        if selection.scrollFrame != nil, !definition.hasScrollFrames {
            throw StateRenderFailure(message: "The state \(definition.name) has one scroll frame, so the frame name must not include a -scroll- number.")
        }
        return Request(name: name, definition: definition, appearance: appearance, scrollFrame: selection.scrollFrame)
    }

    private static func present(_ request: Request) async throws {
        let started = Date()
        let definition = request.definition
        NSApp.appearance = NSAppearance(named: request.appearance == "dark" ? .darkAqua : .aqua)
        StateRenderDisplay.size = definition.displaySize
        let stage = try StateRenderStage(appearance: request.appearance)
        do {
            try StateRenderDesktop.prepare(appearance: request.appearance)
            try StateRenderer.verifyWindows()
            try await StateRenderer.build(definition, on: stage)
            try StateRenderer.verifyWindows()
            try await StateRenderer.settle(stage, milliseconds: definition.name.hasPrefix("quick-look-") ? 1800 : 450)
            let titled = stage.windows.filter { $0 is StateRenderTitledWindow }
            guard titled.count == 1, let window = titled.first else {
                throw StateRenderFailure(message: "The state \(definition.name) produced \(titled.count) titled windows instead of one.")
            }
            let scrollView = stage.primaryScrollView()
            let offsets = StateRenderer.scrollOffsets(scrollView, mode: definition.scroll)
            let offset: CGFloat?
            if let frame = request.scrollFrame {
                guard offsets.indices.contains(frame - 1) else {
                    throw StateRenderFailure(message: "The state \(definition.name) has \(offsets.count) scroll frames, so -scroll-\(frame) does not exist.")
                }
                offset = offsets[frame - 1]
            } else {
                offset = offsets.first ?? nil
            }
            if let offset, let scrollView {
                StateRenderer.apply(offset: offset, to: scrollView)
                try await StateRenderer.settle(stage, milliseconds: 160)
            }
            try StateRenderer.verifyWindows()
            try await requireOrderedInBelowDesktop(window)
            presented = Presented(name: request.name, stage: stage, window: window)
            AppLog.event("rendering", "live_state_ready", fields: ["state": request.name, "windowNumber": String(describing: window.windowNumber),
                                                                   "milliseconds": String(describing: Int(Date().timeIntervalSince(started) * 1000))])
            emit(["event": "live_state_ready", "state": request.name, "windowNumber": window.windowNumber,
                  "windowWidth": Double(window.frame.width), "windowHeight": Double(window.frame.height),
                  "backingScale": Double(window.backingScaleFactor)])
        } catch {
            stage.tearDown()
            throw error
        }
    }

    private static func replace(with name: String) async {
        let request: Request
        do {
            request = try resolve(name)
        } catch {
            reject(error.localizedDescription)
            return
        }
        guard let previous = presented else { return }
        releaseMouse(in: previous.window)
        previous.stage.tearDown()
        presented = nil
        do {
            try await present(request)
        } catch {
            reject(error.localizedDescription)
            do {
                try await present(resolve(previous.name))
            } catch {
                fail("The previous state \(previous.name) could not be presented again after a failed present: \(error.localizedDescription)")
            }
        }
    }

    private static func reject(_ reason: String) {
        AppLog.event("rendering", "live_state", fields: ["outcome": "rejected", "reason": reason])
        emit(["event": "live_state_failed", "reason": reason])
    }

    private static func requireOrderedInBelowDesktop(_ window: NSWindow) async throws {
        for _ in 0..<20 {
            if let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]])?.first,
               info[kCGWindowIsOnscreen as String] as? Bool == true,
               let layer = info[kCGWindowLayer as String] as? Int {
                guard layer < StateRenderer.desktopLevel else {
                    throw StateRenderFailure(message: "Window \(window.windowNumber) is at window-server layer \(layer), not below the desktop layer \(StateRenderer.desktopLevel).")
                }
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw StateRenderFailure(message: "Window \(window.windowNumber) was not ordered in at the window server.")
    }

    nonisolated private static func readCommands() {
        while let line = readLine() {
            DispatchQueue.main.async { MainActor.assumeIsolated { receive(line) } }
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { receive("quit") } }
    }

    private static func receive(_ line: String) {
        guard !isFinishing else { return }
        if isPresenting {
            queuedLines.append(line)
            return
        }
        perform(line)
    }

    private static func drainQueuedLines() {
        while !isPresenting, !isFinishing, !queuedLines.isEmpty {
            perform(queuedLines.removeFirst())
        }
    }

    private static func perform(_ line: String) {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = parts.first else { return }
        let numbers = parts.dropFirst().map { Double($0) }
        func coordinates(_ count: Int) -> [Double]? {
            guard parts.count == count + 1 else { return nil }
            let values = numbers.compactMap { $0 }
            return values.count == count && values.allSatisfy(\.isFinite) ? values : nil
        }
        switch command {
        case "quit" where parts.count == 1:
            quit()
        case "present":
            guard parts.count == 2 else {
                reject("The present command needs exactly one frame name.")
                return
            }
            isPresenting = true
            Task { @MainActor in
                await replace(with: parts[1])
                isPresenting = false
                drainQueuedLines()
            }
        case "click":
            guard let point = coordinates(2) else { return ignore(line) }
            click(x: point[0], y: point[1])
        case "mouse_down", "mouse_dragged", "mouse_up":
            guard let point = coordinates(2) else { return ignore(line) }
            mouse(command, x: point[0], y: point[1])
        case "scroll":
            guard let values = coordinates(4) else { return ignore(line) }
            scroll(x: values[0], y: values[1], deltaX: values[2], deltaY: values[3])
        case "key":
            guard parts.count == 2 || parts.count == 3 else { return ignore(line) }
            key(parts[1], modifiers: parts.count == 3 ? parts[2] : nil, line: line)
        case "type":
            let text = line.drop { $0 == " " }.dropFirst(command.count).dropFirst()
            guard !text.isEmpty else { return ignore(line) }
            typeText(String(text))
        default:
            ignore(line)
        }
    }

    private static func ignore(_ line: String) {
        diagnose("Ignored command: \(line)")
    }

    private static func acknowledge(_ command: String) {
        emit(["event": "input_replayed", "command": command])
        checkSafety()
    }

    private static func acknowledgePendingMouseDown() {
        guard pendingMouseDownAcknowledgement else { return }
        pendingMouseDownAcknowledgement = false
        acknowledge("mouse_down")
    }

    private static func inside(_ window: NSWindow, x: Double, y: Double) -> Bool {
        x >= 0 && y >= 0 && x <= window.frame.width && y <= window.frame.height
    }

    private static func mouseEvent(_ type: NSEvent.EventType, x: Double, y: Double, in window: NSWindow) -> NSEvent? {
        eventNumber += 1
        return NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: window.frame.height - y), modifierFlags: [],
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                  eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
    }

    private static func click(x: Double, y: Double) {
        guard let window = presented?.window else { return }
        guard inside(window, x: x, y: y) else {
            return diagnose("Ignored click at \(x), \(y) outside the \(window.frame.width) by \(window.frame.height) point window frame")
        }
        guard let down = mouseEvent(.leftMouseDown, x: x, y: y, in: window), let up = mouseEvent(.leftMouseUp, x: x, y: y, in: window) else {
            return fail("NSEvent could not create the mouse events for a click at \(x), \(y).")
        }
        acknowledgePendingMouseDown()
        if isDispatchingMouseDown {
            NSApp.postEvent(down, atStart: false)
            NSApp.postEvent(up, atStart: false)
        } else {
            NSApp.postEvent(up, atStart: false)
            NSApp.sendEvent(down)
        }
        isMouseDown = false
        acknowledge("click")
    }

    private static func mouse(_ command: String, x: Double, y: Double) {
        guard let window = presented?.window else { return }
        let type: NSEvent.EventType = command == "mouse_down" ? .leftMouseDown : command == "mouse_up" ? .leftMouseUp : .leftMouseDragged
        if type == .leftMouseDown, !inside(window, x: x, y: y) {
            return diagnose("Ignored mouse_down at \(x), \(y) outside the \(window.frame.width) by \(window.frame.height) point window frame")
        }
        guard let event = mouseEvent(type, x: x, y: y, in: window) else {
            return fail("NSEvent could not create the \(command) event at \(x), \(y).")
        }
        acknowledgePendingMouseDown()
        switch type {
        case .leftMouseDown:
            isMouseDown = true
            if isDispatchingMouseDown {
                NSApp.postEvent(event, atStart: false)
                acknowledge(command)
                return
            }
            isDispatchingMouseDown = true
            pendingMouseDownAcknowledgement = true
            NSApp.sendEvent(event)
            isDispatchingMouseDown = false
            acknowledgePendingMouseDown()
        default:
            if type == .leftMouseUp { isMouseDown = false }
            if isDispatchingMouseDown {
                diagnose("Posted \(command) to the event queue because the previous mouse_down is still being dispatched")
                NSApp.postEvent(event, atStart: false)
            } else {
                NSApp.sendEvent(event)
            }
            acknowledge(command)
        }
    }

    private static func releaseMouse(in window: NSWindow) {
        guard isMouseDown, let up = mouseEvent(.leftMouseUp, x: 0, y: 0, in: window) else { return }
        isMouseDown = false
        if isDispatchingMouseDown { NSApp.postEvent(up, atStart: false) } else { NSApp.sendEvent(up) }
    }

    private static func scroll(x: Double, y: Double, deltaX: Double, deltaY: Double) {
        guard let window = presented?.window else { return }
        guard inside(window, x: x, y: y) else {
            return diagnose("Ignored scroll at \(x), \(y) outside the \(window.frame.width) by \(window.frame.height) point window frame")
        }
        guard let pointer = mouseEvent(.mouseMoved, x: x, y: y, in: window), let source = pointer.cgEvent else {
            return fail("NSEvent could not create the pointer event for a scroll at \(x), \(y).")
        }
        source.type = .scrollWheel
        source.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        for (axis, delta) in [(1, -deltaY), (2, -deltaX)] {
            let whole = Int64(delta.rounded())
            source.setIntegerValueField(axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2, value: whole)
            source.setIntegerValueField(axis == 1 ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2, value: whole)
            source.setDoubleValueField(axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2, value: delta)
        }
        guard let event = NSEvent(cgEvent: source), event.type == .scrollWheel, event.window === window else {
            return fail("NSEvent could not convert the pointer event into a scroll wheel event for window \(window.windowNumber).")
        }
        acknowledgePendingMouseDown()
        NSApp.sendEvent(event)
        acknowledge("scroll")
    }

    private static let functionKeys: [String: (UInt16, String)] = [
        "return": (36, "\r"), "escape": (53, "\u{1b}"), "tab": (48, "\t"), "delete": (51, "\u{7f}"), "space": (49, " "),
        "up": (126, String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)), "down": (125, String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)),
        "left": (123, String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!)), "right": (124, String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!))
    ]

    private static let characterKeys: [Character: UInt16] = {
        var codes: [Character: UInt16] = [:]
        let unshifted: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9), ("b", 11), ("q", 12),
            ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23),
            ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33), ("i", 34),
            ("p", 35), ("l", 37), ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43), ("/", 44), ("n", 45), ("m", 46),
            (".", 47), (" ", 49), ("`", 50)
        ]
        for (character, code) in unshifted { codes[Character(character)] = code }
        for (character, base) in zip("!@#$%^&*()_+{}|:\"<>?~", "1234567890-=[]\\;',./`") { codes[character] = codes[base] }
        for letter in "abcdefghijklmnopqrstuvwxyz" { codes[Character(letter.uppercased())] = codes[letter] }
        return codes
    }()

    private static let shiftedCharacters = Set("!@#$%^&*()_+{}|:\"<>?~ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let shiftedBases: [Character: Character] = Dictionary(uniqueKeysWithValues: zip("!@#$%^&*()_+{}|:\"<>?~", "1234567890-=[]\\;',./`"))

    private static func keyStroke(for character: Character, modifiers: NSEvent.ModifierFlags) -> KeyStroke {
        var flags = modifiers
        if shiftedCharacters.contains(character) { flags.insert(.shift) }
        let base = shiftedBases[character] ?? Character(String(character).lowercased())
        let typed = flags.contains(.shift) && !shiftedCharacters.contains(character) ? String(character).uppercased() : String(character)
        return KeyStroke(keyCode: characterKeys[character] ?? characterKeys[base] ?? 0, characters: typed,
                         charactersIgnoringModifiers: String(base), modifiers: flags)
    }

    private static func key(_ name: String, modifiers: String?, line: String) {
        var flags: NSEvent.ModifierFlags = []
        for modifier in modifiers?.split(separator: "+").map(String.init) ?? [] {
            switch modifier {
            case "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "option": flags.insert(.option)
            case "control": flags.insert(.control)
            default: return ignore(line)
            }
        }
        let stroke: KeyStroke
        if let (code, characters) = functionKeys[name] {
            if ["up", "down", "left", "right"].contains(name) { flags.formUnion([.function, .numericPad]) }
            stroke = KeyStroke(keyCode: code, characters: characters, charactersIgnoringModifiers: characters, modifiers: flags)
        } else if name.count == 1, let character = name.first {
            stroke = keyStroke(for: character, modifiers: flags)
        } else {
            return ignore(line)
        }
        guard send(stroke) else { return }
        acknowledge("key")
    }

    private static func typeText(_ text: String) {
        for character in text {
            guard send(keyStroke(for: character, modifiers: [])) else { return }
        }
        acknowledge("type")
    }

    private static func send(_ stroke: KeyStroke) -> Bool {
        guard let window = presented?.window else { return false }
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: stroke.modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                             windowNumber: window.windowNumber, context: nil, characters: stroke.characters,
                             charactersIgnoringModifiers: stroke.charactersIgnoringModifiers, isARepeat: false, keyCode: stroke.keyCode)
        }
        guard let down = event(.keyDown), let up = event(.keyUp) else {
            fail("NSEvent could not create the key events for \(stroke.characters.debugDescription).")
            return false
        }
        acknowledgePendingMouseDown()
        if stroke.modifiers.isDisjoint(with: [.command, .control]) || !window.performKeyEquivalent(with: down) {
            window.sendEvent(down)
        }
        window.sendEvent(up)
        return true
    }

    private static func checkSafety() {
        guard !isFinishing else { return }
        do {
            let safety = try StateRenderer.verifyWindows()
            displaySafetyChecks += 1
            guard safety != displaySafety else { return }
            displaySafety = safety
            diagnose(["event": "display_safety", "checks": displaySafetyChecks, "policy": safety.activationPolicy,
                      "cachedPolicy": safety.cachedActivationPolicy, "policyRereads": safety.policyRereads, "active": safety.isActive,
                      "windows": safety.windows.map(\.fields)])
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func quit() {
        guard !isFinishing else { return }
        if let window = presented?.window { releaseMouse(in: window) }
        finish()
    }

    private static func finish() -> Never {
        tearDown()
        exit(0)
    }

    private static func fail(_ reason: String) {
        guard !isFinishing else { return }
        AppLog.event("rendering", "live_state", fields: ["outcome": "failed", "reason": reason])
        emit(["event": "live_state_failed", "reason": reason])
        tearDown()
        exit(1)
    }

    private static func tearDown() {
        isFinishing = true
        safetyTimer?.invalidate()
        diagnose(["event": "display_safety_checks", "checks": displaySafetyChecks])
        presented?.stage.tearDown()
        presented = nil
        for window in NSApp.windows { window.orderOut(nil) }
        UpshotStorage.defaults.removePersistentDomain(forName: UpshotStorage.defaultsSuiteName)
        if let root = UpshotStorage.fixtureRoot { try? FileManager.default.removeItem(at: root) }
        if let isolation {
            do {
                let changed = try isolation.changedPaths()
                AppLog.event("rendering", "state_renderer_isolation", fields: ["outcome": changed.isEmpty ? "verified" : "changed", "changedEntries": String(describing: changed.count)])
                diagnose(changed.isEmpty ? "isolation=unchanged" : "isolation=changed paths=\(changed.joined(separator: ", "))")
            } catch {
                diagnose("isolation=unverified error=\(error.localizedDescription)")
            }
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    private static func diagnose(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func diagnose(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        FileHandle.standardError.write(data + Data("\n".utf8))
    }

    private static func emit(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}

extension StateRenderDefinition {
    var hasScrollFrames: Bool {
        if case .frames = scroll { return true }
        return false
    }
}
