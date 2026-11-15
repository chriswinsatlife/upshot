import AppKit
import SwiftUI

final class SheetActionsContentView: NSView {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 560, height: 420)
    private let resultLabel = NSTextField(labelWithString: "Result: none")
    private let trashLabel = NSTextField(labelWithString: "Right-click for Move to Trash")
    private var renameSheet: NSWindow?
    private var nameField: NSTextField?
    private var modalWindow: NSWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let buttons = [
            NSButton(title: "Alert Sheet", target: self, action: #selector(showAlertSheet(_:))),
            NSButton(title: "Rename Sheet", target: self, action: #selector(showRenameSheet(_:))),
            NSButton(title: "Modal Alert", target: self, action: #selector(showModalAlert(_:))),
            NSButton(title: "Modal Window", target: self, action: #selector(showModalWindow(_:))),
        ]
        let trashMenu = NSMenu(title: "Item")
        let trash = NSMenuItem(title: "Move to Trash\u{2026}", action: #selector(confirmTrash(_:)), keyEquivalent: "")
        trash.target = self
        trashMenu.addItem(trash)
        trashLabel.menu = trashMenu
        let stack = NSStackView(views: [resultLabel] + buttons + [trashLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 36),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func record(_ text: String, _ fields: [String: Any]) {
        resultLabel.stringValue = "Result: \(text)"
        FixtureLog.event("sheet_actions_result", fields.merging(["text": text]) { first, _ in first })
    }

    @objc private func showAlertSheet(_ sender: Any?) {
        guard let window else { return }
        FixtureAlert.make().beginSheetModal(for: window) { [weak self] response in
            self?.record("alert sheet \(response.rawValue)", ["kind": "alert_sheet", "response": response.rawValue])
        }
    }

    @objc private func confirmTrash(_ sender: NSMenuItem) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Move the item to the Trash?"
        alert.informativeText = "The item can be restored from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.record("trash \(response.rawValue)", ["kind": "trash_alert_sheet", "response": response.rawValue])
        }
    }

    @objc private func showRenameSheet(_ sender: Any?) {
        guard let window else { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150), styleMask: [.titled], backing: .buffered, defer: true)
        let title = NSTextField(labelWithString: "Rename the item")
        title.font = .boldSystemFont(ofSize: 13)
        let field = NSTextField(string: "Untitled")
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelRename(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let rename = NSButton(title: "Rename", target: self, action: #selector(confirmRename(_:)))
        rename.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, rename])
        let stack = NSStackView(views: [title, field, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 150))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            field.widthAnchor.constraint(equalToConstant: 300),
        ])
        sheet.contentView = content
        sheet.initialFirstResponder = field
        renameSheet = sheet
        nameField = field
        window.beginSheet(sheet) { [weak self] response in
            let name = self?.nameField?.stringValue ?? ""
            self?.record("rename \(response.rawValue) \(name)", ["kind": "rename_sheet", "response": response.rawValue, "name": name])
            self?.renameSheet = nil
        }
    }

    @objc private func cancelRename(_ sender: Any?) {
        guard let renameSheet else { return }
        window?.endSheet(renameSheet, returnCode: .cancel)
    }

    @objc private func confirmRename(_ sender: Any?) {
        guard let renameSheet else { return }
        window?.endSheet(renameSheet, returnCode: .OK)
    }

    @objc private func showModalAlert(_ sender: Any?) {
        let response = FixtureAlert.make().runModal()
        record("modal alert \(response.rawValue)", ["kind": "modal_alert", "response": response.rawValue])
    }

    @objc private func showModalWindow(_ sender: Any?) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: true)
        panel.title = "Export"
        let label = NSTextField(labelWithString: "Export the fixture item?")
        let stop = NSButton(title: "Export", target: self, action: #selector(stopModalWindow(_:)))
        stop.keyEquivalent = "\r"
        let abort = NSButton(title: "Cancel", target: self, action: #selector(abortModalWindow(_:)))
        abort.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, NSStackView(views: [abort, stop])])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        panel.contentView = stack
        modalWindow = panel
        let response = NSApp.runModal(for: panel)
        modalWindow = nil
        record("modal window \(response.rawValue)", ["kind": "modal_window", "response": response.rawValue])
    }

    @objc private func stopModalWindow(_ sender: Any?) {
        NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 7))
    }

    @objc private func abortModalWindow(_ sender: Any?) {
        NSApp.abortModal()
    }
}

struct SwiftUISheetsView: View {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 560, height: 420)
    let size: CGSize
    @State private var result = "none"
    @State private var showsAlert = false
    @State private var showsSheet = false
    @State private var showsDialog = false
    @State private var name = "Untitled"

    var body: some View {
        VStack(spacing: 16) {
            Text("Result: \(result)")
            Button("SwiftUI Alert") { showsAlert = true }
            Button("SwiftUI Sheet") { showsSheet = true }
            Button("SwiftUI Dialog") { showsDialog = true }
        }
        .frame(width: size.width, height: size.height)
        .alert("Delete the fixture item?", isPresented: $showsAlert) {
            Button("Delete", role: .destructive) { record("alert delete") }
            Button("Cancel", role: .cancel) { record("alert cancel") }
        } message: {
            Text("The fixture item is removed from the list.")
        }
        .confirmationDialog("Archive the fixture item?", isPresented: $showsDialog) {
            Button("Archive") { record("dialog archive") }
            Button("Cancel", role: .cancel) { record("dialog cancel") }
        }
        .sheet(isPresented: $showsSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename the item").font(.headline)
                TextField("Name", text: $name).frame(width: 260)
                HStack {
                    Button("Cancel") {
                        record("sheet cancel")
                        showsSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Rename") {
                        record("sheet rename \(name)")
                        showsSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }

    private func record(_ text: String) {
        result = text
        FixtureLog.event("swiftui_sheets_result", ["text": text])
    }
}

struct RightClickTargetsView: View {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 560, height: 420)
    let size: CGSize
    @State private var presses = 0
    @State private var lastAction = "none"

    var body: some View {
        VStack(spacing: 18) {
            Text("Presses: \(presses)")
            Text("Last action: \(lastAction)")
            HStack(spacing: 16) {
                Button("Press") { press("bordered") }
                Button("Styled Press") { press("styled") }
                    .buttonStyle(FixtureFloatingButtonStyle())
                Button("Helped Press") { press("helped") }
                    .buttonStyle(FixtureHoverButtonStyle())
                    .help("Press the helped button")
            }
            Text("Draggable card")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 200, height: 60)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15)))
                .draggable("Uyuni live state fixture card")
                .contextMenu {
                    Button("Open Card") { record("Open Card") }
                    Button("Delete Card") { record("Delete Card") }
                }
            FixtureClickRecognizerTarget { press("click_gesture_recognizer") }
                .frame(width: 180, height: 26)
            Text("Tap target")
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.secondary.opacity(0.18)))
                .onTapGesture { press("tap_gesture") }
            ZStack(alignment: .topTrailing) {
                Text("Shelf card")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 200, height: 60)
                Button("Save") { press("shelf_overlay_save") }
                    .buttonStyle(FixtureFloatingButtonStyle())
                    .padding(4)
            }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.2)))
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onHover { _ in }
                .simultaneousGesture(TapGesture(count: 2).onEnded { record("Open Shelf Card") })
                .draggable(URL(fileURLWithPath: "/System/Library")) {
                    Text("Shelf card").padding()
                }
                .modifier(FixtureDragSessionPhase())
                .contextMenu {
                    Button("Copy Shelf Card") { record("Copy Shelf Card") }
                    Button("Close Shelf Card") { record("Close Shelf Card") }
                }
        }
        .frame(width: size.width, height: size.height)
    }

    private func press(_ kind: String) {
        presses += 1
        FixtureLog.event("right_click_state_button_pressed", ["presses": presses, "button": kind])
    }

    private func record(_ action: String) {
        lastAction = action
        FixtureLog.event("menu_item_action", ["title": action])
    }
}

struct FixtureFloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(configuration.isPressed ? 0.35 : 0.18)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct FixtureDragSessionPhase: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.onDragSessionUpdated { session in
                FixtureLog.event("shelf_card_drag_session", ["phase": String(describing: session.phase)])
            }
        } else {
            content
        }
    }
}

final class ActivationActionsContentView: NSView {
    static let sourceLine = #line
    static let contentSize = CGSize(width: 480, height: 360)
    private let resultLabel = NSTextField(labelWithString: "Active: false")
    private var panel: NSPanel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let buttons = [
            NSButton(title: "Activate Ignoring Other Apps", target: self, action: #selector(activateIgnoringOtherApps(_:))),
            NSButton(title: "Activate", target: self, action: #selector(activateApplication(_:))),
            NSButton(title: "Panel Make Key and Order Front", target: self, action: #selector(panelMakeKeyAndOrderFront(_:))),
            NSButton(title: "Panel Order Front Regardless", target: self, action: #selector(panelOrderFrontRegardless(_:))),
            NSButton(title: "Panel Make Key", target: self, action: #selector(panelMakeKey(_:))),
        ]
        let stack = NSStackView(views: [resultLabel] + buttons)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func report(_ action: String) {
        let active = NSApp.isActive
        resultLabel.stringValue = "Active: \(active)"
        FixtureLog.event("activation_action_result", ["action": action, "isActive": active, "keyWindow": NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? NSNull(),
                                                       "panelIsKey": panel?.isKeyWindow ?? false])
    }

    private func makePanel() -> NSPanel {
        if let panel { return panel }
        let made = FixtureKeyPanel(contentRect: NSRect(x: 900, y: 300, width: 220, height: 60), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        made.title = "Recording Bar"
        made.contentView = NSHostingView(rootView: Text("Recording bar panel").padding())
        panel = made
        return made
    }

    @objc private func activateIgnoringOtherApps(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        report("activate_ignoring_other_apps")
    }

    @objc private func activateApplication(_ sender: Any?) {
        NSApp.activate()
        report("activate")
    }

    @objc private func panelMakeKeyAndOrderFront(_ sender: Any?) {
        makePanel().makeKeyAndOrderFront(nil)
        report("panel_make_key_and_order_front")
    }

    @objc private func panelOrderFrontRegardless(_ sender: Any?) {
        makePanel().orderFrontRegardless()
        report("panel_order_front_regardless")
    }

    @objc private func panelMakeKey(_ sender: Any?) {
        makePanel().makeKey()
        report("panel_make_key")
    }
}

final class FixtureKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class FixtureInactiveWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct FixtureHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FixtureHoverButtonBody(configuration: configuration)
    }
}

private struct FixtureHoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.35 : isHovering ? 0.25 : 0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}

final class FixtureClickRecognizerView: NSView {
    var onClick: () -> Void = {}
    private let label = NSTextField(labelWithString: "Click recognizer")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.2).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func clicked(_ recognizer: NSClickGestureRecognizer) { onClick() }
}

struct FixtureClickRecognizerTarget: NSViewRepresentable {
    let onClick: () -> Void
    func makeNSView(context: Context) -> FixtureClickRecognizerView {
        let view = FixtureClickRecognizerView(frame: .zero)
        view.onClick = onClick
        return view
    }
    func updateNSView(_ nsView: FixtureClickRecognizerView, context: Context) { nsView.onClick = onClick }
}
