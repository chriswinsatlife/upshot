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
    private var fixtureDirectory: URL?

    init(arguments: [String]) {
        failingStateName = arguments.firstIndex(of: "--failing-live-state").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
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
        let lines = ["counter": CounterView.sourceLine, "scrolling-list": ScrollingListView.sourceLine,
                     "text-and-slider": TextAndSliderView.sourceLine, "panel-over-window": PanelView.sourceLine]
        let interactionLines = ["popup-button": PopUpButtonContentView.sourceLine, "menu-picker": MenuPickerView.sourceLine,
                                "draggable-item": DraggableItemView.sourceLine, "save-panel-button": SavePanelButtonView.sourceLine,
                                "open-url-button": OpenURLButtonView.sourceLine, "alert-button": AlertButtonView.sourceLine,
                                "alert-over-window": FixtureAlert.sourceLine, "alert-alone": FixtureAlert.sourceLine, "hosted-settings": HostedSettingsView.sourceLine, "hosted-form": HostedFormView.sourceLine, "grouped-form-menu": GroupedFormMenuView.sourceLine, "capsule-panel": CapsulePanelView.sourceLine]
        let states = ["counter", "scrolling-list", "text-and-slider", "panel-over-window"].map { name in
            LiveStateDescription(name: name, baseState: name, appearance: .light, sourceFile: Self.sourceFile, sourceLine: lines[name] ?? 0)
        } + ["popup-button", "menu-picker", "draggable-item", "save-panel-button", "open-url-button", "alert-button", "alert-over-window", "alert-alone", "hosted-settings", "hosted-form", "grouped-form-menu", "capsule-panel"].map { name in
            LiveStateDescription(name: name, baseState: name, appearance: .light, sourceFile: Self.interactionSourceFile, sourceLine: interactionLines[name] ?? 0)
        } + ["popup-button", "menu-picker", "hosted-settings", "hosted-form", "grouped-form-menu", "capsule-panel"].map { name in
            LiveStateDescription(name: name + "-dark", baseState: name, appearance: .dark, sourceFile: Self.interactionSourceFile, sourceLine: interactionLines[name] ?? 0)
        } + [LiveStateDescription(name: "popup-button-menu-open", baseState: "popup-button", appearance: .light, sourceFile: Self.interactionSourceFile, sourceLine: PopUpButtonContentView.sourceLine)]
        return LiveStateCatalog(states: states)
    }

    func makeLiveStatePresentation(for state: LiveStateDescription) async throws -> LiveStatePresentation {
        var presentation: LiveStatePresentation
        switch state.baseState {
        case "counter":
            presentation = LiveStatePresentation(window: makeWindow(size: Self.baseContentSize) { size in
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

    private func makeWindow(size: CGSize, content: (CGSize) -> AnyView) -> LiveStateWindow {
        let window = LiveStateWindow(contentRect: NSRect(origin: Self.windowOrigin, size: size), styleMask: [.titled],
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
        FileHandle.standardError.write(Data("Usage: UyuniLiveStateFixtureApplication --list-live-states | --present-live-state NAME [--failing-live-state NAME]\n".utf8))
        exit(2)
    }
}
