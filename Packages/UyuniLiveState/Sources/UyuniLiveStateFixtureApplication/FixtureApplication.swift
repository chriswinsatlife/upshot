import AppKit
import SwiftUI
import UyuniLiveState

enum FixtureLog {
    static func event(_ name: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = name
        record["source"] = "fixture_application"
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        FileHandle.standardError.write(data + Data("\n".utf8))
    }
}

@MainActor
final class FixtureApplication: LiveStateApplication {
    static let sourceFile = "packages/uyuni_live_state_swift/Sources/UyuniLiveStateFixtureApplication/FixtureViews.swift"
    static let interactionSourceFile = "packages/uyuni_live_state_swift/Sources/UyuniLiveStateFixtureApplication/FixtureInteractionViews.swift"
    static let windowOrigin = CGPoint(x: 240, y: 240)
    static let baseContentSize = CGSize(width: 480, height: 320)
    static let listContentSize = CGSize(width: 880, height: 620)

    private let failingStateName: String?
    private let stalledStateName: String?
    private let blockingStateName: String?
    private var fixtureDirectory: URL?
    private var helperWindows: [NSWindow] = []

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        failingStateName = value(after: "--failing-live-state")
        stalledStateName = value(after: "--stalled-live-state")
        blockingStateName = value(after: "--blocking-live-state")
    }

    func beginFixtureIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uyuni-live-state-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rows = (1...200).map { "Row \($0)" }
        try JSONSerialization.data(withJSONObject: rows).write(to: directory.appendingPathComponent("rows.json"))
        fixtureDirectory = directory
        FixtureLog.event("fixture_directory_created", ["path": directory.path])
    }

    func endFixtureIsolation() {
        guard let fixtureDirectory else { return }
        let removed = (try? FileManager.default.removeItem(at: fixtureDirectory)) != nil
        FixtureLog.event("fixture_directory_removed", ["path": fixtureDirectory.path, "removed": removed])
    }

    func liveStateCatalog() async throws -> LiveStateCatalog {
        let lines = ["counter": CounterView.sourceLine, "standard-window-buttons": CounterView.sourceLine, "scrolling-list": ScrollingListView.sourceLine,
                     "text-and-slider": TextAndSliderView.sourceLine, "panel-over-window": PanelView.sourceLine]
        let interactionLines = ["popup-button": PopUpButtonContentView.sourceLine, "menu-picker": MenuPickerView.sourceLine,
                                "draggable-item": DraggableItemView.sourceLine, "save-panel-button": SavePanelButtonView.sourceLine,
                                "open-url-button": OpenURLButtonView.sourceLine, "alert-button": AlertButtonView.sourceLine,
                                "alert-over-window": FixtureAlert.sourceLine, "alert-alone": FixtureAlert.sourceLine, "hosted-settings": HostedSettingsView.sourceLine, "hosted-form": HostedFormView.sourceLine, "grouped-form-menu": GroupedFormMenuView.sourceLine, "capsule-panel": CapsulePanelView.sourceLine,
                                "sheet-actions": SheetActionsContentView.sourceLine, "swiftui-sheets": SwiftUISheetsView.sourceLine,
                                "right-click-targets": RightClickTargetsView.sourceLine, "right-click-targets-inactive-window": RightClickTargetsView.sourceLine, "activation-actions": ActivationActionsContentView.sourceLine, "hosted-settings-helper-window": HostedSettingsView.sourceLine]
        let states = ["counter", "standard-window-buttons", "scrolling-list", "text-and-slider", "panel-over-window"].map { name in
            LiveStateDescription(name: name, baseState: name, appearance: .light, sourceFile: Self.sourceFile, sourceLine: lines[name] ?? 0)
        } + ["popup-button", "menu-picker", "draggable-item", "save-panel-button", "open-url-button", "alert-button", "alert-over-window", "alert-alone", "hosted-settings", "hosted-form", "grouped-form-menu", "capsule-panel", "sheet-actions", "swiftui-sheets", "right-click-targets", "right-click-targets-inactive-window", "activation-actions", "hosted-settings-helper-window"].map { name in
            LiveStateDescription(name: name, baseState: name, appearance: .light, sourceFile: Self.interactionSourceFile, sourceLine: interactionLines[name] ?? 0)
        } + ["popup-button", "menu-picker", "hosted-settings", "hosted-form", "grouped-form-menu", "capsule-panel", "sheet-actions", "swiftui-sheets"].map { name in
            LiveStateDescription(name: name + "-dark", baseState: name, appearance: .dark, sourceFile: Self.interactionSourceFile, sourceLine: interactionLines[name] ?? 0)
        } + [LiveStateDescription(name: "popup-button-menu-open", baseState: "popup-button", appearance: .light, sourceFile: Self.interactionSourceFile, sourceLine: PopUpButtonContentView.sourceLine)]
        return LiveStateCatalog(states: states)
    }

    func makeLiveStatePresentation(for state: LiveStateDescription) async throws -> LiveStatePresentation {
        if state.name == stalledStateName {
            FixtureLog.event("stalled_presentation_begun", ["state": state.name])
            try await Task.sleep(for: .seconds(3600))
        }
        if state.name == blockingStateName {
            FixtureLog.event("blocking_presentation_begun", ["state": state.name])
            usleep(3_600_000_000)
        }
        var presentation: LiveStatePresentation
        switch state.baseState {
        case "counter":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize) { size in
                AnyView(CounterView(model: CounterModel(), size: size))
            })
        case "standard-window-buttons":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize, styleMask: [.titled, .closable, .miniaturizable, .resizable]) { size in
                AnyView(CounterView(model: CounterModel(), size: size))
            })
        case "scrolling-list":
            let rows = try loadRows()
            presentation = LiveStatePresentation(window: makeWindow(size: Self.listContentSize) { size in
                AnyView(ScrollingListView(rows: rows, size: size))
            })
        case "text-and-slider":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize) { size in
                AnyView(TextAndSliderView(size: size))
            })
        case "panel-over-window":
            let window = makeWindow(size: Self.baseContentSize) { size in AnyView(CounterView(model: CounterModel(), size: size)) }
            let panel = LiveStatePanel(contentRect: NSRect(x: window.frame.minX + 360, y: window.frame.minY + 170, width: 240, height: 160),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
            panel.contentView = NSHostingView(rootView: PanelView(model: PanelModel()))
            presentation = LiveStatePresentation(regionWindows: [window, panel])
        case "popup-button":
            let window = makeWindow(size: PopUpButtonContentView.contentSize) { _ in AnyView(EmptyView()) }
            let content = PopUpButtonContentView(frame: NSRect(origin: .zero, size: PopUpButtonContentView.contentSize))
            window.contentView = content
            presentation = LiveStatePresentation(window: window)
            if state.name.hasSuffix("-menu-open") { presentation.openInitialMenu = { content.openPopUpMenu() } }
        case "menu-picker":
            presentation = LiveStatePresentation(window: makeWindow(size: MenuPickerView.contentSize) { AnyView(MenuPickerView(size: $0)) })
        case "draggable-item":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize) { AnyView(DraggableItemView(size: $0)) })
        case "save-panel-button":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize) { AnyView(SavePanelButtonView(size: $0)) })
        case "open-url-button":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize) { AnyView(OpenURLButtonView(size: $0)) })
        case "alert-button":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize) { AnyView(AlertButtonView(size: $0)) })
        case "alert-over-window":
            let window = makeWindow(size: Self.baseContentSize) { size in AnyView(CounterView(model: CounterModel(), size: size)) }
            presentation = LiveStatePresentation(alert: FixtureAlert.make(), over: window) { response in
                FixtureLog.event("fixture_alert_button_response", ["response": response.rawValue])
            }
        case "hosted-settings":
            let window = LiveStateWindow(contentRect: NSRect(origin: Self.windowOrigin, size: HostedSettingsView.contentSize),
                                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            let host = NSHostingView(rootView: HostedSettingsView())
            host.safeAreaRegions = []
            host.sizingOptions = []
            window.contentView = host
            presentation = LiveStatePresentation(window: window)
        case "hosted-settings-helper-window":
            let window = LiveStateWindow(contentRect: NSRect(origin: Self.windowOrigin, size: HostedSettingsView.contentSize),
                                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            let host = NSHostingView(rootView: HostedSettingsView())
            host.safeAreaRegions = []
            host.sizingOptions = []
            window.contentView = host
            let helperWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
            helperWindows = [helperWindow]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: helperWindow.windowNumber, context: nil, subtype: 0, data1: 0, data2: 0) {
                    NSApp.postEvent(event, atStart: false)
                    FixtureLog.event("helper_window_event_posted", ["windowNumber": helperWindow.windowNumber])
                }
            }
            presentation = LiveStatePresentation(window: window, tearDown: { [weak self] in self?.helperWindows = [] })
        case "hosted-form":
            let window = LiveStateWindow(contentRect: NSRect(origin: Self.windowOrigin, size: HostedFormView.contentSize),
                                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: HostedFormView())
            presentation = LiveStatePresentation(window: window)
        case "grouped-form-menu":
            let window = LiveStateWindow(contentRect: NSRect(origin: Self.windowOrigin, size: GroupedFormMenuView.contentSize),
                                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: GroupedFormMenuView())
            presentation = LiveStatePresentation(window: window)
        case "capsule-panel":
            let panel = LiveStatePanel(contentRect: NSRect(x: 600, y: 600, width: CapsulePanelView.contentSize.width, height: CapsulePanelView.contentSize.height),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.contentView = NSHostingView(rootView: CapsulePanelView())
            presentation = LiveStatePresentation(window: panel)
            presentation.menuMargin = NSEdgeInsets(top: 40, left: 120, bottom: 260, right: 120)
        case "sheet-actions":
            let window = makeWindow(size: SheetActionsContentView.contentSize) { _ in AnyView(EmptyView()) }
            window.contentView = SheetActionsContentView(frame: NSRect(origin: .zero, size: SheetActionsContentView.contentSize))
            presentation = LiveStatePresentation(window: window)
        case "swiftui-sheets":
            presentation = LiveStatePresentation(window: makeWindow(size: SwiftUISheetsView.contentSize) { AnyView(SwiftUISheetsView(size: $0)) })
        case "right-click-targets":
            presentation = LiveStatePresentation(window: makeWindow(size: RightClickTargetsView.contentSize) { AnyView(RightClickTargetsView(size: $0)) })
        case "right-click-targets-inactive-window":
            let window = FixtureInactiveWindow(contentRect: NSRect(origin: Self.windowOrigin, size: RightClickTargetsView.contentSize), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: RightClickTargetsView(size: RightClickTargetsView.contentSize).background(Color(nsColor: .windowBackgroundColor)))
            presentation = LiveStatePresentation(window: window)
        case "activation-actions":
            let window = makeWindow(size: ActivationActionsContentView.contentSize) { _ in AnyView(EmptyView()) }
            window.contentView = ActivationActionsContentView(frame: NSRect(origin: .zero, size: ActivationActionsContentView.contentSize))
            presentation = LiveStatePresentation(window: window)
        case "alert-alone":
            presentation = LiveStatePresentation(alert: FixtureAlert.make()) { response in
                FixtureLog.event("fixture_alert_button_response", ["response": response.rawValue])
            }
        default:
            throw LiveStateFailure("The fixture application builds no state named \(state.name).")
        }
        if state.name == failingStateName {
            presentation.regionFrame = CGRect(x: -20_000, y: -20_000, width: 10, height: 10)
            FixtureLog.event("failing_region_assigned", ["state": state.name])
        }
        return presentation
    }

    private func loadRows() throws -> [String] {
        guard let fixtureDirectory else { throw LiveStateFailure("The fixture directory was not created.") }
        let data = try Data(contentsOf: fixtureDirectory.appendingPathComponent("rows.json"))
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [String] else {
            throw LiveStateFailure("The fixture rows file does not hold a list of strings.")
        }
        return rows
    }

    private func makeWindow(size: CGSize, styleMask: NSWindow.StyleMask = [.titled], content: (CGSize) -> AnyView) -> LiveStateWindow {
        let window = LiveStateWindow(contentRect: NSRect(origin: Self.windowOrigin, size: size), styleMask: styleMask,
                                     backing: .buffered, defer: false)
        window.title = "Uyuni Live State Fixture"
        window.contentView = NSHostingView(rootView: content(size))
        return window
    }
}

@main
enum FixtureApplicationEntry {
    @MainActor
    static func main() {
        LiveStateRuntime.runIfRequested { FixtureApplication(arguments: CommandLine.arguments) }
        FileHandle.standardError.write(Data("Usage: UyuniLiveStateFixtureApplication --list-live-states | --present-live-state NAME [--failing-live-state NAME] [--stalled-live-state NAME] [--blocking-live-state NAME]\n".utf8))
        exit(2)
    }
}
