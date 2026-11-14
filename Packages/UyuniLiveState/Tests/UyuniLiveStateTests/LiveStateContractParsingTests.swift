import Testing
@testable import UyuniLiveState

struct LiveStateContractParsingTests {
    @Test func launchArgumentsSelectTheContractMode() {
        #expect(LiveStateLaunchRequest(arguments: ["app"]) == nil)
        #expect(LiveStateLaunchRequest(arguments: ["app", "--list-live-states"]) == .listLiveStates)
        #expect(LiveStateLaunchRequest(arguments: ["app", "--present-live-state", "counter"]) == .presentLiveState("counter"))
        #expect(LiveStateLaunchRequest(arguments: ["app", "--fixture", "--present-live-state", "counter", "--verbose"]) == .presentLiveState("counter"))
        #expect(LiveStateLaunchRequest(arguments: ["app", "--present-live-state"]) == .invalid(reason: "The argument --present-live-state must be followed by one state name."))
        #expect(LiveStateLaunchRequest(arguments: ["app", "--present-live-state", "--list-live-states"]).map { if case .invalid = $0 { true } else { false } } == true)
    }

    @Test func inputLinesFollowTheContractGrammar() {
        #expect(LiveStateCommand.parse("click 240 272.5") == .command(.click(x: 240, y: 272.5)))
        #expect(LiveStateCommand.parse("mouse_dragged 10 -4") == .command(.mouseDragged(x: 10, y: -4)))
        #expect(LiveStateCommand.parse("scroll 240 180 0 -250") == .command(.scroll(x: 240, y: 180, deltaX: 0, deltaY: -250)))
        #expect(LiveStateCommand.parse("key a command+shift") == .command(.key(name: "a", modifiers: [.command, .shift])))
        #expect(LiveStateCommand.parse("key return") == .command(.key(name: "return", modifiers: [])))
        #expect(LiveStateCommand.parse("type  two spaces kept") == .command(.type(" two spaces kept")))
        #expect(LiveStateCommand.parse("present settings-light") == .command(.present("settings-light")))
        #expect(LiveStateCommand.parse("present") == .rejectedPresent(reason: "The present command needs exactly one state name."))
        #expect(LiveStateCommand.parse("quit") == .command(.quit))
        #expect(LiveStateCommand.parse("") == .empty)
        for line in ["click 1", "click a b", "scroll 1 2 3", "key enter", "key a hyper", "type", "resize 10 10", "click nan 2"] {
            guard case .ignored = LiveStateCommand.parse(line) else {
                Issue.record("The line \(line.debugDescription) was not ignored.")
                continue
            }
        }
    }

    @Test func typedCharactersCarryUSLayoutKeyCodesAndShift() {
        let upper = LiveStateKeyStroke.typed("U")
        #expect(upper.keyCode == 32)
        #expect(upper.modifiers.contains(.shift))
        #expect(upper.charactersIgnoringModifiers == "u")
        let exclamation = LiveStateKeyStroke.typed("!")
        #expect(exclamation.keyCode == 18)
        #expect(exclamation.charactersIgnoringModifiers == "1")
        #expect(LiveStateKeyStroke.named("up", modifiers: [])?.modifiers.contains(.function) == true)
    }

    @Test func catalogRejectsNamesThePresentCommandCannotCarry() {
        let state = LiveStateDescription(name: "two words", baseState: "two", appearance: .light, sourceFile: "File.swift", sourceLine: 1)
        let duplicate = LiveStateDescription(name: "same", baseState: "same", appearance: .dark, sourceFile: "File.swift", sourceLine: 2)
        #expect(LiveStateCatalog(states: [state]).validationFailures().count == 1)
        #expect(LiveStateCatalog(states: [duplicate, duplicate]).validationFailures().count == 1)
        #expect(LiveStateCatalog(states: [duplicate]).validationFailures().isEmpty)
    }
}
