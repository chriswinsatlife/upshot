import AppKit
import ObjectiveC
import Testing
@testable import UyuniLiveState

@MainActor
struct LiveStateInteractionGuardTests {
    static let originalImplementations: [String: IMP] = {
        _ = NSApplication.shared
        var implementations: [String: IMP] = [:]
        for (owner, selector): (AnyClass, String) in guardedMethods {
            implementations[selector] = class_getMethodImplementation(owner, NSSelectorFromString(selector))
        }
        return implementations
    }()

    static let guardedMethods: [(AnyClass, String)] = [
        (NSWorkspace.self, "openURL:"), (NSWorkspace.self, "openURL:configuration:completionHandler:"),
        (NSSavePanel.self, "runModal"), (NSAlert.self, "runModal"), (NSWindow.self, "beginSheet:completionHandler:"),
        (NSView.self, "beginDraggingSessionWithItems:event:source:"), (NSRunningApplication.self, "activateWithOptions:"),
    ]

    init() {
        _ = Self.originalImplementations
        #expect(LiveStateInteractionGuards.install().isEmpty)
    }

    func requireReplaced(_ owner: AnyClass, _ selector: String) throws {
        let original = try #require(Self.originalImplementations[selector])
        try #require(class_getMethodImplementation(owner, NSSelectorFromString(selector)) != original)
    }

    @Test func workspaceOpensReturnFailureWithoutOpening() throws {
        try requireReplaced(NSWorkspace.self, "openURL:")
        #expect(!NSWorkspace.shared.open(URL(string: "https://example.com")!))
    }

    @Test func filePanelsReturnCancelWithoutRunning() throws {
        try requireReplaced(NSSavePanel.self, "runModal")
        #expect(NSSavePanel().runModal() == .cancel)
        #expect(NSOpenPanel().runModal() == .cancel)
    }

    @Test func modalAlertsReturnTheirEscapeButtonOrAbort() throws {
        try requireReplaced(NSAlert.self, "runModal")
        let confirmation = NSAlert()
        confirmation.addButton(withTitle: "Delete")
        confirmation.addButton(withTitle: "Cancel")
        #expect(confirmation.runModal() == .alertSecondButtonReturn)
        let notice = NSAlert()
        notice.addButton(withTitle: "Continue")
        #expect(notice.runModal() == .abort)
    }

    @Test func sheetsCompleteWithAbortWithoutAttaching() async throws {
        try requireReplaced(NSWindow.self, "beginSheet:completionHandler:")
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20), styleMask: [.titled], backing: .buffered, defer: true)
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            parent.beginSheet(sheet) { continuation.resume(returning: $0) }
        }
        #expect(response == .abort)
        #expect(parent.attachedSheet == nil)
    }

    @Test func draggingSessionsDoNotBegin() throws {
        try requireReplaced(NSView.self, "beginDraggingSessionWithItems:event:source:")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.titled], backing: .buffered, defer: false)
        let view = DraggingSourceView(frame: window.contentLayoutRect)
        window.contentView = view
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let item = NSDraggingItem(pasteboardWriter: "text" as NSString)
        let session: NSDraggingSession? = view.beginDraggingSession(with: [item], event: event, source: view)
        #expect(session == nil)
    }

    @Test func otherApplicationsAreNotActivated() throws {
        try requireReplaced(NSRunningApplication.self, "activateWithOptions:")
        #expect(!NSRunningApplication.current.activate(options: []))
    }

    @Test func alertPresentationRehostsTheAlertAboveItsWindowAndReportsButtons() throws {
        let context = LiveStateWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: true)
        let alert = NSAlert()
        alert.messageText = "Delete the item?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        var responses: [NSApplication.ModalResponse] = []
        let presentation = LiveStatePresentation(alert: alert, over: context) { responses.append($0) }
        #expect(presentation.windows.count == 2)
        #expect(presentation.windows.first === context)
        let alertWindow = try #require(presentation.windows.last)
        #expect(alertWindow.styleMask.rawValue & LiveStatePresentation.modalAlertPanelStyleBits == 0)
        #expect(alertWindow.frame.maxY <= context.frame.maxY)
        #expect(abs(alertWindow.frame.midX - context.frame.midX) <= 1)
        alert.buttons[1].performClick(nil)
        alert.buttons[0].performClick(nil)
        #expect(responses == [.alertSecondButtonReturn, .alertFirstButtonReturn])
        presentation.tearDown?()
        #expect(alert.buttons.allSatisfy { $0.target == nil })
    }
}

final class DraggingSourceView: NSView, NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
