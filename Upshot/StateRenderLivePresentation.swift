import AppKit
import SwiftUI

enum StateRenderLivePresentation {
    private static var stage: StateRenderStage?
    private static var window: NSWindow?
    private static var isolation: StateRenderIsolation?
    private static var activity: NSObjectProtocol?
    private static var safetyTimer: Timer?
    private static var isFinishing = false

    static func run() -> Never {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        guard arguments.count == 1, let name = arguments.first, !name.hasPrefix("--") else {
            FileHandle.standardError.write(Data(StateRenderer.usage.utf8))
            emit(["event": "live_state_failed", "reason": "The arguments must be --present-live-state followed by one frame name."])
            exit(2)
        }
        let app = NSApplication.shared
        guard app.setActivationPolicy(.prohibited) else {
            emit(["event": "live_state_failed", "reason": "The activation policy could not be set to prohibited."])
            exit(1)
        }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Present a live render state")
        Task { @MainActor in
            do {
                try await present(name)
            } catch {
                fail(error.localizedDescription)
            }
        }
        app.run()
        exit(1)
    }

    private static func present(_ name: String) async throws {
        isolation = try StateRenderIsolation()
        let selection = StateRenderer.Selection(name)
        guard let appearance = selection.appearance else {
            throw StateRenderFailure(message: "The frame name \(name) has no -light or -dark appearance suffix.")
        }
        let definitions = try await StateRenderer.loadDefinitions()
        guard let definition = definitions.first(where: { $0.name == selection.state }) else {
            throw StateRenderFailure(message: "Unknown state: \(name)")
        }
        guard case .window(let kind) = definition.placement, [.settings, .library, .annotate, .studio].contains(kind) else {
            throw StateRenderFailure(message: "The state \(definition.name) is not placed in one Settings, Library, Annotate, or Studio window.")
        }
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        StateRenderDisplay.size = definition.displaySize
        let stage = try StateRenderStage(appearance: appearance)
        self.stage = stage
        try StateRenderDesktop.prepare(appearance: appearance)
        try StateRenderer.verifyWindows()
        try await StateRenderer.build(definition, on: stage)
        try StateRenderer.verifyWindows()
        try await StateRenderer.settle(stage, milliseconds: 450)
        guard let window = stage.windows.first(where: { $0 is StateRenderTitledWindow }) else {
            throw StateRenderFailure(message: "The state \(definition.name) produced no titled window.")
        }
        self.window = window
        let scrollView = stage.primaryScrollView()
        let offsets = StateRenderer.scrollOffsets(scrollView, mode: definition.scroll)
        let offset: CGFloat?
        if offsets.count > 1 {
            guard let frame = selection.scrollFrame, offsets.indices.contains(frame - 1) else {
                throw StateRenderFailure(message: "The state \(definition.name) has \(offsets.count) scroll frames, so the frame name must include -scroll-1 through -scroll-\(offsets.count).")
            }
            offset = offsets[frame - 1]
        } else {
            guard selection.scrollFrame == nil else {
                throw StateRenderFailure(message: "The state \(definition.name) has one scroll frame, so the frame name must not include a -scroll- number.")
            }
            offset = offsets.first ?? nil
        }
        if let offset, let scrollView {
            StateRenderer.apply(offset: offset, to: scrollView)
            try await StateRenderer.settle(stage, milliseconds: 160)
        }
        try StateRenderer.verifyWindows()
        try await requireOrderedInBelowDesktop(window)
        safetyTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { checkSafety() }
        }
        AppLog.event("rendering", "live_state_ready", fields: ["state": name, "windowNumber": String(describing: window.windowNumber)])
        emit(["event": "live_state_ready", "state": name, "windowNumber": window.windowNumber,
              "windowWidth": Double(window.frame.width), "windowHeight": Double(window.frame.height),
              "backingScale": Double(window.backingScaleFactor)])
        Thread.detachNewThread { readCommands() }
    }

    private static func requireOrderedInBelowDesktop(_ window: NSWindow) async throws {
        for _ in 0..<20 {
            if let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]])?.first,
               info[kCGWindowIsOnscreen as String] as? Bool == true,
               let layer = info[kCGWindowLayer as String] as? Int {
                guard layer < StateRenderer.desktopLevel else {
                    throw StateRenderFailure(message: "Window \(window.windowNumber) is at window-server layer \(layer), not below the desktop layer \(StateRenderer.desktopLevel).")
                }
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw StateRenderFailure(message: "Window \(window.windowNumber) was not ordered in at the window server.")
    }

    nonisolated private static func readCommands() {
        while let line = readLine() {
            DispatchQueue.main.async { MainActor.assumeIsolated { perform(line) } }
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { quit() } }
    }

    private static func perform(_ line: String) {
        guard !isFinishing else { return }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        switch parts.first {
        case "quit" where parts.count == 1:
            quit()
        case "click" where parts.count == 3:
            guard let x = Double(parts[1]), let y = Double(parts[2]), x.isFinite, y.isFinite else {
                diagnose("Ignored click command with non-numeric coordinates: \(line)")
                return
            }
            click(x: x, y: y)
        default:
            diagnose("Ignored unknown command: \(line)")
        }
    }

    private static func click(x: Double, y: Double) {
        guard let window else { return }
        let frame = window.frame
        guard x >= 0, y >= 0, x <= frame.width, y <= frame.height else {
            diagnose("Ignored click at \(x), \(y) outside the \(frame.width) by \(frame.height) point window frame")
            return
        }
        let location = NSPoint(x: x, y: frame.height - y)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                               pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else {
            fail("NSEvent could not create the mouse events for a click at \(x), \(y).")
            return
        }
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
        emit(["event": "click_replayed", "x": x, "y": y])
        checkSafety()
    }

    private static func checkSafety() {
        guard !isFinishing else { return }
        do {
            try StateRenderer.verifyWindows()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private static func quit() {
        guard !isFinishing else { return }
        tearDown()
        exit(0)
    }

    private static func fail(_ reason: String) {
        guard !isFinishing else { return }
        AppLog.event("rendering", "live_state", fields: ["outcome": "failed", "reason": reason])
        emit(["event": "live_state_failed", "reason": reason])
        tearDown()
        exit(1)
    }

    private static func tearDown() {
        isFinishing = true
        safetyTimer?.invalidate()
        stage?.tearDown()
        for window in NSApp.windows { window.orderOut(nil) }
        UpshotStorage.defaults.removePersistentDomain(forName: UpshotStorage.fixtureIdentifier)
        if let root = UpshotStorage.fixtureRoot { try? FileManager.default.removeItem(at: root) }
        if let isolation {
            do {
                let changed = try isolation.changedPaths()
                AppLog.event("rendering", "state_renderer_isolation", fields: ["outcome": changed.isEmpty ? "verified" : "changed", "changedEntries": String(describing: changed.count)])
                diagnose(changed.isEmpty ? "isolation=unchanged" : "isolation=changed paths=\(changed.joined(separator: ", "))")
            } catch {
                diagnose("isolation=unverified error=\(error.localizedDescription)")
            }
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    private static func diagnose(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func emit(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
