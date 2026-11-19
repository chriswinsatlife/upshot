import AppKit
import ScreenCaptureKit
import SwiftUI
import UyuniLiveState

enum StateRenderLivePresentation {
    static let regionMargin: CGFloat = 40
    private static var signalSources: [DispatchSourceSignal] = []
    private static let privateBundleSourceEnvironmentKey = "UYUNI_LIVE_STATE_PRIVATE_BUNDLE_SOURCE"

    static func run(_ request: LiveStateLaunchRequest) -> Never {
        recordProcessEnd()
        if ProcessInfo.processInfo.environment[privateBundleSourceEnvironmentKey] == nil, Bundle.main.bundleURL.pathExtension == "app" {
            AppLog.shared.removeEmptyCrashFile()
        }
        LiveStateRuntime.run(request) { UpshotLiveStates() }
    }

    nonisolated static func timestamp() -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(Date())
    }

    nonisolated static func log(_ event: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = event
        record["processIdentifier"] = Int(ProcessInfo.processInfo.processIdentifier)
        record["uptime"] = ProcessInfo.processInfo.systemUptime
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        FileHandle.standardError.write(data + Data("\n".utf8))
    }

    private static func recordProcessEnd() {
        atexit {
            StateRenderLivePresentation.log("process_exit", ["time": StateRenderLivePresentation.timestamp()])
        }
        let queue = DispatchQueue(label: "co.chrisyork.upshot.live-state-signals")
        signalSources = [SIGTERM, SIGHUP, SIGINT].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                log("process_signal", ["signal": Int(number), "time": timestamp()])
                AppLog.shared.removeEmptyCrashFile()
                signal(number, SIG_DFL)
                raise(number)
            }
            source.resume()
            return source
        }
    }

    static func regionFrame(of windows: [NSWindow]) async throws -> CGRect {
        let display = try StateRenderDisplay.frame
        var content = CGRect.null
        for window in windows {
            content = content.union(await drawnFrame(of: window, display: display))
        }
        guard !content.isNull else { return display }
        return content.insetBy(dx: -regionMargin, dy: -regionMargin).integral.intersection(display)
    }

    private static func drawnFrame(of window: NSWindow, display: CGRect) async -> CGRect {
        let frame = window.frame
        guard window is StateRenderWindow, window.isVisible, !window.isOpaque, frame.size != display.size, CGPreflightScreenCaptureAccess() else { return frame }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let shareable = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { return frame }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(frame.width * StateRenderDisplay.scale)
            configuration.height = Int(frame.height * StateRenderDisplay.scale)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: shareable), configuration: configuration)
            guard let drawn = drawnPixelBounds(of: image) else { return frame }
            let scale = CGFloat(image.width) / frame.width
            let measured = CGRect(x: frame.minX + drawn.minX / scale, y: frame.maxY - drawn.maxY / scale,
                                  width: drawn.width / scale, height: drawn.height / scale).integral.intersection(frame)
            if measured != frame {
                log("region_window_drawn_frame", ["windowNumber": window.windowNumber,
                                                  "frame": [frame.minX, frame.minY, frame.width, frame.height],
                                                  "drawn": [measured.minX, measured.minY, measured.width, measured.height]])
            }
            return measured
        } catch {
            log("region_window_drawn_frame_unmeasured", ["windowNumber": window.windowNumber, "error": error.localizedDescription])
            return frame
        }
    }

    private static func drawnPixelBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let alpha = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for row in 0..<height {
            for column in 0..<width where alpha[row * width + column] > 8 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

@MainActor
final class UpshotLiveStates: LiveStateApplication {
    private struct SharedState {
        let appearance = NSApp.appearance
        let displaySize = StateRenderDisplay.size
        let desktopImage = StateRenderDesktop.image
        let scenario = StateRenderer.scenario
        let preferences = UpshotStorage.defaults.persistentDomain(forName: UpshotStorage.defaultsSuiteName)
        let settingsTab = SettingsNavigation.shared.selectedTab
        let settingsSearchText = SettingsNavigation.shared.searchText
        let settingsDetail = SettingsNavigation.shared.renderDetail

        func restore() {
            NSApp.appearance = appearance
            StateRenderDisplay.size = displaySize
            StateRenderDesktop.image = desktopImage
            StateRenderer.scenario = scenario
            UpshotStorage.defaults.setPersistentDomain(preferences ?? [:], forName: UpshotStorage.defaultsSuiteName)
            SettingsNavigation.shared.prepareRenderState(selectedTab: settingsTab, searchText: settingsSearchText, detail: settingsDetail)
        }
    }

    private var isolation: StateRenderIsolation?
    private var definitions: [String: StateRenderDefinition] = [:]

    func beginFixtureIsolation() async throws {
        isolation = try StateRenderIsolation()
    }

    func liveStateCatalog() async throws -> LiveStateCatalog {
        let catalog = try await StateRenderer.loadDefinitions()
        definitions = Dictionary(uniqueKeysWithValues: catalog.map { ($0.name, $0) })
        let states = catalog.flatMap { definition in
            LiveStateAppearance.allCases.map { appearance in
                LiveStateDescription(name: definition.name + "-" + appearance.rawValue, baseState: definition.name, appearance: appearance,
                                     sourceFile: definition.sourceFile, sourceLine: definition.line)
            }
        }
        AppLog.event("rendering", "live_states", fields: ["states": String(describing: states.count), "unsupported": "0"])
        return LiveStateCatalog(states: states)
    }

    func makeLiveStatePresentation(for state: LiveStateDescription) async throws -> LiveStatePresentation {
        StateRenderLivePresentation.log("present_started", ["state": state.name, "time": StateRenderLivePresentation.timestamp()])
        guard let definition = definitions[state.baseState] else {
            throw LiveStateFailure("The state \(state.baseState) is not in the render catalog.")
        }
        let started = Date()
        let appearance = state.appearance.rawValue
        NSApp.appearance = NSAppearance(named: state.appearance.appearanceName)
        StateRenderDisplay.size = definition.displaySize
        let stage = try StateRenderStage(appearance: appearance)
        do {
            try StateRenderDesktop.prepare(appearance: appearance)
            try StateRenderer.verifyWindows()
            var alert: (context: NSWindow?, alert: NSAlert)?
            if case .alert = definition.placement {
                alert = try await StateRenderer.buildAlert(definition, on: stage)
            } else {
                try await StateRenderer.build(definition, on: stage)
            }
            try StateRenderer.verifyWindows()
            try await StateRenderer.settle(stage, milliseconds: definition.name.hasPrefix("quick-look-") ? 1800 : 450)
            let scrollView = stage.primaryScrollView()
            if let offset = StateRenderer.scrollOffsets(scrollView, mode: definition.scroll).first ?? nil, let scrollView {
                StateRenderer.apply(offset: offset, to: scrollView)
                try await StateRenderer.settle(stage, milliseconds: 160)
            }
            try StateRenderer.verifyWindows()
            let presentation = try await presentation(for: definition, stage: stage, alert: alert)
            AppLog.event("rendering", "live_state_built", fields: ["state": state.name, "windows": String(describing: presentation.windows.count),
                                                                   "milliseconds": String(describing: Int(Date().timeIntervalSince(started) * 1000))])
            return presentation
        } catch let failure as LiveStateFailure {
            stage.tearDown()
            throw failure
        } catch {
            stage.tearDown()
            throw LiveStateFailure(error.localizedDescription)
        }
    }

    private func presentation(for definition: StateRenderDefinition, stage: StateRenderStage,
                              alert: (context: NSWindow?, alert: NSAlert)?) async throws -> LiveStatePresentation {
        let tearDown: @MainActor () -> Void = { stage.tearDown() }
        guard let wallpaper = stage.windows.first else { throw LiveStateFailure("The state \(definition.name) has no wallpaper window.") }
        if let alert {
            var presentation = LiveStatePresentation(alert: alert.alert, over: alert.context, tearDown: tearDown)
            guard let alertWindow = presentation.windows.last else { throw LiveStateFailure("The alert of \(definition.name) has no window.") }
            if alert.context == nil { alertWindow.center() }
            alertWindow.contentView?.addSubview(StateRenderEditCommandView(frame: .zero))
            presentation.backdropWindow = wallpaper
            presentation.regionFrame = try await StateRenderLivePresentation.regionFrame(of: Array(stage.windows.dropFirst()) + [alertWindow])
            return presentation
        }
        if case .window = definition.placement {
            let titled = stage.windows.filter { $0 is StateRenderTitledWindow }
            guard titled.count == 1, let window = titled.first else {
                throw LiveStateFailure("The state \(definition.name) produced \(titled.count) titled windows instead of one.")
            }
            return LiveStatePresentation(window: window, tearDown: tearDown)
        }
        let windows = Array(stage.windows.dropFirst())
        guard !windows.isEmpty else { throw LiveStateFailure("The state \(definition.name) produced no window above the wallpaper window.") }
        return LiveStatePresentation(regionWindows: windows, backdropWindow: wallpaper,
                                     regionFrame: try await StateRenderLivePresentation.regionFrame(of: windows), tearDown: tearDown)
    }

    func sharedStateRestoration() -> (@MainActor () -> Void)? {
        let shared = SharedState()
        return { shared.restore() }
    }

    func endFixtureIsolation() {
        UpshotStorage.defaults.removePersistentDomain(forName: UpshotStorage.defaultsSuiteName)
        if let root = UpshotStorage.fixtureRoot { try? FileManager.default.removeItem(at: root) }
        guard let isolation else { return }
        do {
            let changed = try isolation.changedPaths()
            AppLog.event("rendering", "state_renderer_isolation", fields: ["outcome": changed.isEmpty ? "verified" : "changed", "changedEntries": String(describing: changed.count)])
            StateRenderLivePresentation.log("isolation_compared", ["changedPaths": changed])
        } catch {
            StateRenderLivePresentation.log("isolation_compared", ["error": error.localizedDescription])
        }
    }
}

enum StateRenderKeyRouting {
    private static let editActions: [String: Selector] = [
        "a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:))
    ]

    static func performEditCommand(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard UpshotStorage.isPresentingLiveState, event.type == .keyDown,
              event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
              let action = editActions[(event.charactersIgnoringModifiers ?? "").lowercased()],
              let responder = window.firstResponder, responder.tryToPerform(action, with: nil) else { return false }
        StateRenderLivePresentation.log("edit_command_performed", ["action": NSStringFromSelector(action), "windowNumber": window.windowNumber])
        return true
    }

    static func offersKeyEquivalentFirst(_ event: NSEvent) -> Bool {
        UpshotStorage.isPresentingLiveState && event.type == .keyDown && event.modifierFlags.isDisjoint(with: [.command, .control])
    }
}

final class StateRenderEditCommandView: NSView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let window else { return false }
        return StateRenderKeyRouting.performEditCommand(event, in: window)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
