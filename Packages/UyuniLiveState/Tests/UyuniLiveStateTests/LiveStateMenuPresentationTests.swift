import AppKit
import Testing
@testable import UyuniLiveState

@MainActor
final class LiveStateMenuActionTarget: NSObject {
    var chosen: [String] = []
    @objc func choose(_ sender: NSMenuItem) { chosen.append(sender.title) }
}

@MainActor
struct LiveStateMenuPresentationTests {
    init() {
        _ = NSApplication.shared
    }

    func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        return window
    }

    @Test func pointerCommandsParse() {
        #expect(LiveStateCommand.parse("mouse_moved 10 20") == .command(.mouseMoved(x: 10, y: 20)))
        #expect(LiveStateCommand.parse("right_click 5 6") == .command(.rightClick(x: 5, y: 6)))
    }

    @Test func layoutCollapsesSeparatorsAndSkipsHiddenItems() {
        let menu = NSMenu()
        menu.addItem(.separator())
        menu.addItem(withTitle: "One", action: nil, keyEquivalent: "s")
        menu.addItem(.separator())
        menu.addItem(.separator())
        let hidden = menu.addItem(withTitle: "Hidden", action: nil, keyEquivalent: "")
        hidden.isHidden = true
        menu.addItem(withTitle: "Two", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let layout = LiveStateMenuLayout(menu: menu, minimumWidth: 0)
        #expect(layout.rows.map { $0.kind == .separator ? "-" : $0.item.title } == ["One", "-", "Two"])
        #expect(LiveStateMenuLayout.keyEquivalentText(of: menu.items[1]) == "\u{2318}S")
    }

    @Test func clickingAnItemPerformsItsActionAndClosesTheMenu() throws {
        let window = makeWindow()
        let target = LiveStateMenuActionTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false
        for title in ["Alpha", "Beta"] {
            let item = NSMenuItem(title: title, action: #selector(LiveStateMenuActionTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        menu.items[0].isEnabled = false
        let presenter = LiveStateMenuPresenter()
        #expect(presenter.present(menu, in: window, anchor: .item(nil, topLeft: NSPoint(x: 20, y: 280)), minimumWidth: 0, source: "test"))
        let panel = try #require(presenter.panels.first)
        let rows = panel.rowsView.layout.rows
        func screenPoint(row: Int) -> NSPoint {
            window.convertPoint(toScreen: NSPoint(x: panel.frameInWindow.midX, y: panel.frameInWindow.maxY - rows[row].top - rows[row].height / 2))
        }
        #expect(presenter.click(at: screenPoint(row: 0)) == .insideMenu)
        #expect(presenter.isShowing)
        #expect(presenter.click(at: screenPoint(row: 1)) == .chose)
        #expect(!presenter.isShowing)
        #expect(target.chosen == ["Beta"])
        #expect(window.contentView?.subviews.isEmpty == true)
    }

    @Test func outsideClickAndEscapeCloseWithoutAction() {
        let window = makeWindow()
        let target = LiveStateMenuActionTarget()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Alpha", action: #selector(LiveStateMenuActionTarget.choose(_:)), keyEquivalent: "")
        item.target = target
        menu.addItem(item)
        let presenter = LiveStateMenuPresenter()
        #expect(presenter.present(menu, in: window, anchor: .item(nil, topLeft: NSPoint(x: 20, y: 280)), minimumWidth: 0, source: "test"))
        #expect(presenter.click(at: window.convertPoint(toScreen: NSPoint(x: 390, y: 10))) == .closedOutside)
        #expect(presenter.present(menu, in: window, anchor: .item(nil, topLeft: NSPoint(x: 20, y: 280)), minimumWidth: 0, source: "test"))
        #expect(presenter.key("escape") == "closed")
        #expect(!presenter.isShowing)
        #expect(target.chosen.isEmpty)
    }

    @Test func keyboardNavigationSkipsDisabledItemsAndOpensSubmenus() throws {
        let window = makeWindow()
        let target = LiveStateMenuActionTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let disabled = menu.addItem(withTitle: "Disabled", action: nil, keyEquivalent: "")
        disabled.isEnabled = false
        let parent = menu.addItem(withTitle: "More", action: nil, keyEquivalent: "")
        parent.submenu = NSMenu(title: "More")
        let child = NSMenuItem(title: "Child", action: #selector(LiveStateMenuActionTarget.choose(_:)), keyEquivalent: "")
        child.target = target
        parent.submenu?.addItem(child)
        let presenter = LiveStateMenuPresenter()
        #expect(presenter.present(menu, in: window, anchor: .item(nil, topLeft: NSPoint(x: 20, y: 280)), minimumWidth: 0, source: "test"))
        #expect(presenter.key("down") == "highlighted")
        #expect(presenter.panels[0].rowsView.highlightedRow == 1)
        #expect(presenter.key("right") == "opened_submenu")
        #expect(presenter.panels.count == 2)
        #expect(presenter.key("return") == "chose")
        #expect(target.chosen == ["Child"])
    }

    @Test func choosingFromAPopUpButtonChangesItsSelection() throws {
        let window = makeWindow()
        let popUp = NSPopUpButton(frame: NSRect(x: 100, y: 150, width: 160, height: 24), pullsDown: false)
        popUp.addItems(withTitles: ["Red", "Green", "Blue"])
        window.contentView?.addSubview(popUp)
        let cell = try #require(popUp.cell as? NSPopUpButtonCell)
        let presenter = LiveStateMenuPresenter()
        #expect(presenter.present(try #require(popUp.menu), in: window, anchor: .popUpButton(cell, popUp.frame), minimumWidth: 0, source: "test"))
        let panel = try #require(presenter.panels.first)
        #expect(panel.rowsView.highlightedRow == 0)
        #expect(presenter.key("down") == "highlighted")
        #expect(presenter.key("return") == "chose")
        #expect(popUp.titleOfSelectedItem == "Green")
    }

    @Test func aChosenItemRunsItsActionWhenOnlyTheMenuHoldsItsTarget() throws {
        let window = makeWindow()
        let menu = NSMenu()
        var chosen: [String] = []
        let presenter = LiveStateMenuPresenter()
        do {
            let target = LiveStateMenuClosureTarget { chosen.append($0) }
            let item = NSMenuItem(title: "Kept", action: #selector(LiveStateMenuClosureTarget.choose(_:)), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
            #expect(presenter.present(menu, in: window, anchor: .item(nil, topLeft: NSPoint(x: 20, y: 280)), minimumWidth: 0, source: "test"))
        }
        #expect(menu.items[0].target != nil)
        #expect(presenter.key("down") == "highlighted")
        #expect(presenter.key("return") == "chose")
        #expect(chosen == ["Kept"])
    }

    @Test func aMenuWithMarginIsDrawnInTheMenuWindowAroundTheState() throws {
        let window = makeWindow()
        window.setFrameOrigin(NSPoint(x: 500, y: 500))
        let menuWindow = LiveStateMenuWindow(around: [window], margin: NSEdgeInsets(top: 10, left: 20, bottom: 200, right: 20))
        #expect(menuWindow.frame == NSRect(x: 480, y: 300, width: 440, height: 510))
        let menu = NSMenu()
        for title in ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen"] { menu.addItem(withTitle: title, action: nil, keyEquivalent: "") }
        let presenter = LiveStateMenuPresenter()
        presenter.menuWindowProvider = { menuWindow }
        #expect(presenter.present(menu, in: window, anchor: .item(nil, topLeft: NSPoint(x: 20, y: 40)), minimumWidth: 0, source: "test"))
        #expect(presenter.hostWindow === menuWindow)
        let panel = try #require(presenter.panels.first)
        #expect(panel.frameInWindow.height == panel.rowsView.layout.size.height)
        #expect(menuWindow.convertToScreen(panel.frameInWindow).minY < window.frame.minY)
    }
}

@MainActor
final class LiveStateMenuClosureTarget: NSObject {
    let handler: (String) -> Void
    init(_ handler: @escaping (String) -> Void) { self.handler = handler }
    @objc func choose(_ sender: NSMenuItem) { handler(sender.title) }
}
