import AppKit
import Testing
@testable import UyuniLiveState

@MainActor
@Suite(.serialized)
struct LiveStateSheetPresentationTests {
    init() {
        _ = NSApplication.shared
        #expect(LiveStateInteractionGuards.install().isEmpty)
    }

    func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 420))
        return window
    }

    func keyEvent(_ characters: String, keyCode: UInt16, in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                      characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    @Test func anAlertSheetIsShownInItsWindowAndEndsWithThePressedButton() throws {
        let window = makeWindow()
        let presenter = LiveStateSheetPresenter.shared
        presenter.stageContains = { $0 === window }
        defer { presenter.stageContains = { _ in false } }
        let alert = NSAlert()
        alert.messageText = "Delete the item?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        var responses: [NSApplication.ModalResponse] = []
        alert.beginSheetModal(for: window) { responses.append($0) }
        let sheet = try #require(presenter.active)
        #expect(sheet.kind == .alertSheet)
        #expect(sheet.container.isDescendant(of: try #require(window.contentView)))
        #expect(sheet.frameInWindow.maxY <= window.contentLayoutRect.maxY)
        #expect(presenter.blocks(window, screenPoint: window.convertPoint(toScreen: NSPoint(x: 5, y: 5))))
        #expect(!presenter.blocks(window, screenPoint: window.convertPoint(toScreen: NSPoint(x: sheet.frameInWindow.midX, y: sheet.frameInWindow.midY))))
        #expect(presenter.performKey(try keyEvent("\u{1b}", keyCode: LiveStateKeyStroke.escapeKeyCode, in: window)))
        #expect(responses == [.alertSecondButtonReturn])
        #expect(presenter.active == nil)
        #expect(window.contentView?.subviews.isEmpty == true)
        #expect(alert.window.contentView?.subviews.isEmpty == false)
    }

    @Test func aWindowSheetEndsWithTheCodeGivenToEndSheet() throws {
        let window = makeWindow()
        let presenter = LiveStateSheetPresenter.shared
        presenter.stageContains = { $0 === window }
        defer { presenter.stageContains = { _ in false } }
        let source = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: true)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let field = NSTextField(string: "Untitled")
        field.frame = NSRect(x: 20, y: 60, width: 200, height: 22)
        content.addSubview(field)
        source.contentView = content
        var responses: [NSApplication.ModalResponse] = []
        window.beginSheet(source) { responses.append($0) }
        let sheet = try #require(presenter.active)
        #expect(sheet.kind == .windowSheet)
        #expect(sheet.frameInWindow.size == CGSize(width: 300, height: 120))
        window.endSheet(source, returnCode: .OK)
        #expect(responses == [.OK])
        #expect(source.contentView === content)
        #expect(presenter.active == nil)
    }

    @Test func anAlertSheetEndsWithTheCodeGivenToEndSheetForTheAlertWindow() throws {
        let window = makeWindow()
        let presenter = LiveStateSheetPresenter.shared
        presenter.stageContains = { $0 === window }
        defer { presenter.stageContains = { _ in false } }
        let alert = NSAlert()
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        var responses: [NSApplication.ModalResponse] = []
        alert.beginSheetModal(for: window) { responses.append($0) }
        #expect(presenter.active?.kind == .alertSheet)
        window.endSheet(alert.window, returnCode: .alertThirdButtonReturn)
        #expect(responses == [.alertThirdButtonReturn])
        #expect(presenter.active == nil)
    }

    @Test func aReplayedEventBecomesTheApplicationsCurrentEvent() throws {
        let window = makeWindow()
        let stale = try #require(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0))
        LiveStateCurrentEvent.set(stale)
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        #expect(LiveStateCurrentEvent.isAvailable)
        LiveStateCurrentEvent.set(up)
        #expect(NSApp.currentEvent === up)
    }

    @Test func aSheetForAWindowOutsideTheStateIsNotShown() {
        let window = makeWindow()
        let alert = NSAlert()
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        #expect(!LiveStateSheetPresenter.shared.presentAlertSheet(alert, for: window, completion: nil))
        #expect(LiveStateSheetPresenter.shared.active == nil)
    }

    @Test func aMenuInTheMenuWindowKeepsRoomForItsShadow() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let insets = LiveStateMenuMetrics.shadowInsets
        let placed = LiveStateMenuPresenter.clamp(CGRect(x: 300, y: 10, width: 120, height: 100), in: bounds, reserving: insets)
        #expect(placed.maxX <= bounds.maxX - insets.right)
        #expect(placed.minY >= bounds.minY + insets.bottom)
        #expect(placed.size == CGSize(width: 120, height: 100))
        let windowPlaced = LiveStateMenuPresenter.clamp(CGRect(x: 300, y: 10, width: 120, height: 100), in: bounds, reserving: LiveStateMenuMetrics.noInsets)
        #expect(windowPlaced.maxX == bounds.maxX - LiveStateMenuMetrics.windowMargin)
    }
}
