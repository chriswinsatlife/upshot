import AppKit
import Testing
@testable import UyuniLiveState

@MainActor
struct LiveStateWindowLevelGuardTests {
    init() {
        _ = NSApplication.shared
        #expect(LiveStateWindowPlacement.installWindowLevelGuards().isEmpty)
    }

    @Test func levelsAtOrAboveTheDesktopAreClampedBelowIt() {
        let window = LiveStateWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true)
        window.level = .floating
        #expect(window.level.rawValue == LiveStateWindowPlacement.desktopLevel - 1)
        window.level = NSWindow.Level(rawValue: LiveStateWindowPlacement.desktopLevel - 5)
        #expect(window.level.rawValue == LiveStateWindowPlacement.desktopLevel - 5)
    }

    @Test func childWindowsAreLoweredToTheParentLevelAndIgnoreMouseEvents() {
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true)
        parent.level = NSWindow.Level(rawValue: LiveStateWindowPlacement.desktopLevel - 3)
        let child = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 5, height: 5), styleMask: [.borderless], backing: .buffered, defer: true)
        #expect(child.level == .normal)
        parent.addChildWindow(child, ordered: .above)
        #expect(child.level == parent.level)
        #expect(child.ignoresMouseEvents)
        parent.removeChildWindow(child)
    }

    @Test func aWindowOrderedInAtTheNormalLevelIsLoweredFirst() {
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 1, height: 1), styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.isReleasedWhenClosed = false
        #expect(window.level == .normal)
        window.orderFront(nil)
        #expect(window.level.rawValue == LiveStateWindowPlacement.desktopLevel - 1)
        #expect(window.ignoresMouseEvents)
        window.orderOut(nil)
    }
}
