import AppKit
import SwiftUI

final class PopUpButtonContentView: NSView {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 560, height: 420)
    private let popUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pullDownButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let contextButton = NSButton(title: "Show Context Menu", target: nil, action: nil)
    private let rightClickLabel = NSTextField(labelWithString: "Right-click for options")
    private let edgePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let selectionLabel = NSTextField(labelWithString: "Selected: First")
    private let actionLabel = NSTextField(labelWithString: "Action: none")
    private let edgeLabel = NSTextField(labelWithString: "Edge: Item 10")
    private let pressButton = NSButton(title: "Press", target: nil, action: nil)
    private let pressLabel = NSTextField(labelWithString: "Presses: 0")
    private var presses = 0
    private var color = "Blue"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for (title, key) in [("First", "1"), ("Second", "2"), ("Third", ""), ("Fourth", "4")] {
            popUpButton.addItem(withTitle: title)
            popUpButton.lastItem?.keyEquivalent = key
            popUpButton.lastItem?.keyEquivalentModifierMask = .command
        }
        popUpButton.item(withTitle: "Third")?.isEnabled = false
        popUpButton.autoenablesItems = false
        popUpButton.menu?.insertItem(.separator(), at: 3)
        popUpButton.target = self
        popUpButton.action = #selector(selectionChanged(_:))

        pullDownButton.addItem(withTitle: "Actions")
        pullDownButton.menu?.addItem(makeItem("Duplicate", key: "d"))
        pullDownButton.menu?.addItem(makeItem("Rename", key: "r"))
        pullDownButton.menu?.addItem(.separator())
        let share = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
        share.submenu = NSMenu(title: "Share")
        share.submenu?.addItem(makeItem("Mail", key: ""))
        share.submenu?.addItem(makeItem("Messages", key: ""))
        pullDownButton.menu?.addItem(share)
        let delete = makeItem("Delete", key: "")
        delete.isEnabled = false
        pullDownButton.menu?.addItem(delete)
        pullDownButton.autoenablesItems = false

        contextButton.target = self
        contextButton.action = #selector(showContextMenu(_:))
        rightClickLabel.menu = makeContextMenu()

        edgePopUpButton.addItems(withTitles: (1...10).map { "Item \($0)" })
        edgePopUpButton.selectItem(at: 9)
        edgePopUpButton.target = self
        edgePopUpButton.action = #selector(edgeSelectionChanged(_:))

        pressButton.target = self
        pressButton.action = #selector(pressed(_:))
        let contextRow = NSStackView(views: [contextButton, rightClickLabel])
        contextRow.spacing = 24
        let stack = NSStackView(views: [selectionLabel, popUpButton, actionLabel, pullDownButton, contextRow, pressLabel, pressButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let edgeStack = NSStackView(views: [edgeLabel, edgePopUpButton])
        edgeStack.spacing = 8
        edgeStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(edgeStack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            popUpButton.widthAnchor.constraint(equalToConstant: 200),
            pullDownButton.widthAnchor.constraint(equalToConstant: 140),
            edgeStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            edgeStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            edgePopUpButton.widthAnchor.constraint(equalToConstant: 110),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeItem(_ title: String, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Arrange")
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: "Arrange"))
        menu.addItem(makeItem("Bring Forward", key: "f"))
        menu.addItem(makeItem("Send Backward", key: "b"))
        menu.addItem(.separator())
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        colorItem.submenu = NSMenu(title: "Color")
        for name in ["Red", "Green", "Blue"] {
            let item = makeItem(name, key: "")
            item.state = name == color ? .on : .off
            colorItem.submenu?.addItem(item)
        }
        menu.addItem(colorItem)
        let lock = makeItem("Lock", key: "l")
        lock.isEnabled = false
        menu.addItem(lock)
        return menu
    }

    @objc private func showContextMenu(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else { return }
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: sender)
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        if sender.menu?.title == "Color" {
            color = sender.title
            rightClickLabel.menu = makeContextMenu()
        }
        actionLabel.stringValue = "Action: \(sender.title)"
        FixtureLog.event("menu_item_action", ["title": sender.title, "menu": sender.menu?.title ?? ""])
    }

    func openPopUpMenu() {
        popUpButton.performClick(nil)
    }

    @objc private func selectionChanged(_ sender: NSPopUpButton) {
        selectionLabel.stringValue = "Selected: \(sender.titleOfSelectedItem ?? "")"
        FixtureLog.event("pop_up_selection_changed", ["selection": sender.titleOfSelectedItem ?? ""])
    }

    @objc private func edgeSelectionChanged(_ sender: NSPopUpButton) {
        edgeLabel.stringValue = "Edge: \(sender.titleOfSelectedItem ?? "")"
        FixtureLog.event("edge_pop_up_selection_changed", ["selection": sender.titleOfSelectedItem ?? ""])
    }

    @objc private func pressed(_ sender: NSButton) {
        presses += 1
        pressLabel.stringValue = "Presses: \(presses)"
        FixtureLog.event("pop_up_state_button_pressed", ["presses": presses])
    }
}

struct MenuPickerView: View {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 560, height: 420)
    let size: CGSize
    @State private var selection = "Small"
    @State private var lastAction = "none"
    @State private var presses = 0
    @State private var listening = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Selected: \(selection)")
            Picker("Size", selection: $selection) {
                Text("Small").tag("Small")
                Text("Medium").tag("Medium")
                Text("Large").tag("Large")
            }
            .pickerStyle(.menu)
            .frame(width: 220)
            Text("Last action: \(lastAction)")
            Menu {
                Button("Rename Item") { record("Rename Item") }
                    .keyboardShortcut("r")
                Button("Archive Item") { record("Archive Item") }
                    .disabled(true)
                Divider()
                Picker("Size", selection: $selection) {
                    Text("Small").tag("Small")
                    Text("Large").tag("Large")
                }
                .pickerStyle(.inline)
                Menu("Move To") {
                    Button("Inbox") { record("Move To Inbox") }
                    Button("Archive") { record("Move To Archive") }
                }
            } label: {
                Text("Item Actions")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.18)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            Text("Right-click for options")
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.5)))
                .contextMenu {
                    Button("Copy Name") { record("Copy Name") }
                    Button("Show Details") { record("Show Details") }
                }
            Text("Presses: \(presses)")
            Button("Press") {
                presses += 1
                FixtureLog.event("picker_state_button_pressed", ["presses": presses])
            }
            Toggle("Wake listening", isOn: $listening)
                .toggleStyle(.switch)
                .onChange(of: listening) { _, value in FixtureLog.event("picker_state_toggle_changed", ["isOn": value]) }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: selection) { _, value in FixtureLog.event("picker_selection_changed", ["selection": value]) }
    }

    private func record(_ action: String) {
        lastAction = action
        FixtureLog.event("menu_item_action", ["title": action])
    }
}

struct DraggableItemView: View {
    static let sourceLine = #line
    let size: CGSize
    @State private var presses = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Drag me")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 200, height: 70)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.85, green: 0.9, blue: 1)))
                .draggable("Uyuni live state fixture text")
            FileDragSource()
                .frame(width: 200, height: 44)
            Text("Presses: \(presses)")
            Button("Press") {
                presses += 1
                FixtureLog.event("draggable_state_button_pressed", ["presses": presses])
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct SavePanelButtonView: View {
    static let sourceLine = #line
    let size: CGSize
    @State private var result = "none"

    var body: some View {
        VStack(spacing: 16) {
            Text("Save panel response: \(result)")
            Button("Save File") {
                let response = NSSavePanel().runModal()
                result = String(response.rawValue)
                FixtureLog.event("save_panel_returned", ["response": response.rawValue])
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct OpenURLButtonView: View {
    static let sourceLine = #line
    let size: CGSize
    @State private var result = "none"

    var body: some View {
        VStack(spacing: 16) {
            Text("Opened: \(result)")
            Button("Open Example Website") {
                let opened = NSWorkspace.shared.open(URL(string: "https://example.com")!)
                result = String(opened)
                FixtureLog.event("open_url_returned", ["opened": opened])
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct AlertButtonView: View {
    static let sourceLine = #line
    let size: CGSize
    @State private var result = "none"

    var body: some View {
        VStack(spacing: 16) {
            Text("Alert response: \(result)")
            Button("Show Alert") {
                let response = FixtureAlert.make().runModal()
                result = String(response.rawValue)
                FixtureLog.event("alert_returned", ["response": response.rawValue])
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

@MainActor
enum FixtureAlert {
    static let sourceLine = #line
    static func make() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Delete the fixture item?"
        alert.informativeText = "The fixture item is removed from the list."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    private let label = NSTextField(labelWithString: "Drag file")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor(red: 0.9, green: 0.95, blue: 0.88, alpha: 1).cgColor
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: "/System/Library") as NSURL)
        item.setDraggingFrame(bounds, contents: nil)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        FixtureLog.event("file_drag_source_mouse_down")
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

struct FileDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> FileDragSourceView { FileDragSourceView(frame: .zero) }
    func updateNSView(_ nsView: FileDragSourceView, context: Context) {}
}

final class FixtureMenuChoice: NSObject {
    let handler: (String) -> Void
    init(_ handler: @escaping (String) -> Void) { self.handler = handler }
    @objc func choose(_ item: NSMenuItem) { handler(item.title) }
}

struct HostedSettingsPopUp: View {
    let title: String
    let options: [String]
    @Binding var value: String

    var body: some View {
        HStack {
            if !title.isEmpty {
                Text(title)
                Spacer()
            }
            Button(action: open) {
                HStack(spacing: 8) {
                    Text(value)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func open() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = FixtureMenuChoice { value = $0; FixtureLog.event("hosted_menu_choice", ["title": title, "value": $0]) }
        var current: NSMenuItem?
        for option in options {
            let item = NSMenuItem(title: option, action: #selector(FixtureMenuChoice.choose(_:)), keyEquivalent: "")
            item.target = target
            item.state = option == value ? .on : .off
            menu.addItem(item)
            if option == value { current = item }
        }
        FixtureLog.event("hosted_pop_up_current_event", ["type": NSApp.currentEvent.map { Int($0.type.rawValue) } ?? -1, "windowNumber": NSApp.currentEvent?.windowNumber ?? -1])
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        withExtendedLifetime(target) { _ = menu.popUp(positioning: current, at: point, in: view) }
    }
}

struct HostedSettingsView: View {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 520, height: 380)
    @State private var microphone = "Built-in Microphone"
    @State private var language = "English"
    @State private var retention = "30 days"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Recording").font(.title3.weight(.semibold))
                HostedSettingsPopUp(title: "Microphone", options: ["Built-in Microphone", "Studio Display", "AirPods Pro"], value: $microphone)
                HostedSettingsPopUp(title: "Language", options: ["English", "German", "Japanese", "Spanish"], value: $language)
                HostedSettingsPopUp(title: "Keep recordings", options: ["7 days", "30 days", "1 year", "Forever"], value: $retention)
                Text("Microphone: \(microphone), Language: \(language), Keep: \(retention)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 48)
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
    }
}

struct CapsulePanelView: View {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 240, height: 44)
    @State private var mode = "Screen"

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color.red).frame(width: 12, height: 12)
            Text("Recording").font(.system(size: 13, weight: .semibold))
            Spacer()
            HostedSettingsPopUp(title: "", options: ["Screen", "Window", "Area", "Camera Only", "Screen and Camera", "Audio Only"], value: $mode)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(Capsule().fill(Color(white: 0.97)))
    }
}

struct HostedFormView: View {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 520, height: 380)
    @State private var choice = "First"
    @State private var presses = 0

    var body: some View {
        Form {
            Section("Selected") {
                LabeledContent("Choice") {
                    Menu {
                        Picker("Choice", selection: $choice) {
                            Text("First").tag("First")
                            Text("Second").tag("Second")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Text(choice)
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
                LabeledContent("Presses") {
                    Button("Press \(presses)") {
                        presses += 1
                        FixtureLog.event("hosted_form_button_pressed", ["presses": presses])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .onChange(of: choice) { _, value in FixtureLog.event("hosted_form_choice_changed", ["choice": value]) }
    }
}

struct GroupedFormMenuView: View {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 760, height: 600)
    @State private var choice = "First"

    var body: some View {
        Form {
            Section("Selected") {
                LabeledContent("Choice") {
                    Menu {
                        Picker("Choice", selection: $choice) {
                            Text("First").tag("First")
                            Text("Second").tag("Second")
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Text(choice)
                    }
                    .menuStyle(.button)
                    .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .onChange(of: choice) { _, value in FixtureLog.event("grouped_form_choice_changed", ["choice": value]) }
    }
}
