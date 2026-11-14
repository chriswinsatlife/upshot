import AppKit

@MainActor
struct PresentedLiveState {
    let description: LiveStateDescription
    let presentation: LiveStatePresentation
    let stack: [NSWindow]
    let regionFrame: CGRect?
    let regionOrigin: CGPoint
    let frontWindow: NSWindow
    let menuWindow: NSWindow?

    var inputWindows: [NSWindow] { presentation.windows.reversed().filter(\.isVisible) }
    var visibleStack: [NSWindow] { stack.filter(\.isVisible) }
    var modalWindow: NSWindow? { presentation.modalWindow.flatMap { $0.isVisible ? $0 : nil } }
    var frame: CGRect { regionFrame ?? frontWindow.frame }
    var size: CGSize { frame.size }

    func screenPoint(x: Double, y: Double) -> CGPoint {
        CGPoint(x: frame.minX + x, y: frame.maxY - y)
    }

    func contains(x: Double, y: Double) -> Bool {
        x >= 0 && y >= 0 && x <= size.width && y <= size.height
    }

    func window(at point: CGPoint) -> NSWindow? {
        inputWindows.first { $0.frame.contains(point) }
    }
}

@MainActor
struct LiveStateCommandRecord {
    let word: String
    let received: ContinuousClock.Instant
    var fields: [String: Any] = [:]

    init(word: String) {
        self.word = word
        received = ContinuousClock.now
    }
}

@MainActor
final class LiveStateSession {
    private let application: any LiveStateApplication
    private let request: LiveStateLaunchRequest
    private let started = ContinuousClock.now
    private var catalog = LiveStateCatalog(states: [])
    private var statesByName: [String: LiveStateDescription] = [:]
    private var unsupportedReasons: [String: String] = [:]
    private var presented: PresentedLiveState?
    private var activity: NSObjectProtocol?
    private var safetyTimer: Timer?
    private var isFinishing = false
    private var isPresenting = false
    private var queuedLines: [String] = []
    private var isDispatchingMouseDown = false
    private var pendingMouseDown: LiveStateCommandRecord?
    private var isMouseDown = false
    private var isMouseDownBlocked = false
    private var isPointerGestureConsumedByMenu = false
    private let menuPresenter = LiveStateMenuPresenter.shared
    private var mouseTarget: NSWindow?
    private var keyTarget: NSWindow?
    private var eventNumber = 0
    private var lastSafety: LiveStateDisplaySafety?
    private var safetySummary = LiveStateSafetySummary()
    private var isIsolationBegun = false
    private var commandOutcomes: [String: Int] = [:]
    private var presentedStateNames: [String] = []
    private var buildingStack: [NSWindow] = []
    private var buildingMenuWindow: NSWindow?

    init(application: any LiveStateApplication, request: LiveStateLaunchRequest) {
        self.application = application
        self.request = request
    }

    func start() {
        LiveStateMenuPresenter.shared.menuWindowProvider = { [self] in buildingMenuWindow ?? presented?.menuWindow }
        LiveStateInteractionGuards.stageWindows = { [self] in
            Set(((presented?.stack ?? []) + buildingStack).map(ObjectIdentifier.init))
        }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Present a live state for the Uyuni canvas")
        LiveStateLog.event("latency_critical_activity_begun", ["options": ["userInitiated", "latencyCritical"]])
        Task { @MainActor in
            do {
                try await loadCatalog()
                switch request {
                case .listLiveStates:
                    writeCatalog()
                    finish(status: 0, reason: nil)
                case .presentLiveState(let name):
                    try await presentFirst(name)
                case .invalid(let reason):
                    fail(reason)
                }
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    private func loadCatalog() async throws {
        let begun = ContinuousClock.now
        try await application.beginFixtureIsolation()
        isIsolationBegun = true
        LiveStateLog.event("fixture_isolation_begun", ["milliseconds": LiveStateLog.milliseconds(since: begun)])
        let loaded = try await application.liveStateCatalog()
        let failures = loaded.validationFailures()
        guard failures.isEmpty else { throw LiveStateFailure(failures.joined(separator: " ")) }
        catalog = loaded
        statesByName = Dictionary(uniqueKeysWithValues: loaded.states.map { ($0.name, $0) })
        unsupportedReasons = Dictionary(uniqueKeysWithValues: loaded.unsupported.map { ($0.name, $0.reason) })
        LiveStateLog.event("live_state_catalog_loaded", ["states": loaded.states.count, "unsupported": loaded.unsupported.count,
                                                         "milliseconds": LiveStateLog.milliseconds(since: begun)])
    }

    private func writeCatalog() {
        let states: [[String: Any]] = catalog.states.map {
            ["name": $0.name, "baseState": $0.baseState, "appearance": $0.appearance.rawValue, "sourceFile": $0.sourceFile, "sourceLine": $0.sourceLine]
        }
        let unsupported: [[String: Any]] = catalog.unsupported.map { ["name": $0.name, "reason": $0.reason] }
        LiveStateOutput.write(["event": "live_states", "states": states, "unsupported": unsupported])
    }

    private func resolve(_ name: String) throws -> LiveStateDescription {
        if let state = statesByName[name] { return state }
        if let reason = unsupportedReasons[name] { throw LiveStateFailure("The state \(name) cannot be presented: \(reason)") }
        throw LiveStateFailure("The catalog names no live state \(name).")
    }

    private func presentFirst(_ name: String) async throws {
        let begun = ContinuousClock.now
        let first = try await build(try resolve(name))
        presented = first
        announce(first, milliseconds: LiveStateLog.milliseconds(since: begun))
        let timer = Timer(timeInterval: 0.25, repeats: true) { [self] _ in
            MainActor.assumeIsolated { checkSafety() }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
        startReadingCommands()
    }

    private func build(_ description: LiveStateDescription) async throws -> PresentedLiveState {
        let begun = ContinuousClock.now
        NSApp.appearance = NSAppearance(named: description.appearance.appearanceName)
        let presentation = try await application.makeLiveStatePresentation(for: description)
        let menuWindow = presentation.hasMenuMargin ? LiveStateMenuWindow(around: presentation.stackWindows, margin: presentation.menuMargin) : nil
        let stack = presentation.stackWindows + (menuWindow.map { [$0] } ?? [])
        buildingStack = stack
        buildingMenuWindow = menuWindow
        defer {
            buildingStack = []
            buildingMenuWindow = nil
        }
        do {
            guard let front = presentation.windows.last else {
                throw LiveStateFailure("The app returned no window for the state \(description.name).")
            }
            guard Set(stack.map(ObjectIdentifier.init)).count == stack.count else {
                throw LiveStateFailure("The app returned the same window more than once for the state \(description.name).")
            }
            for window in stack { try LiveStateWindowPlacement.prepare(window, appearance: description.appearance) }
            LiveStateWindowPlacement.orderIn(stack)
            for window in stack {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
            try await Task.sleep(for: presentation.settleDuration)
            for window in stack {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                if window.hasShadow { window.invalidateShadow() }
            }
            for window in stack { try await LiveStateWindowPlacement.requireOrderedInBelowDesktop(window) }
            if let openInitialMenu = presentation.openInitialMenu {
                openInitialMenu()
                for window in stack { window.displayIfNeeded() }
                LiveStateLog.event("initial_menu_opened", ["state": description.name, "menuShown": menuPresenter.isShowing])
            }
            var regionFrame: CGRect?
            var regionOrigin = CGPoint.zero
            if presentation.presentsRegion {
                let frame = presentation.regionFrame ?? stack.dropFirst().reduce(stack[0].frame) { $0.union($1.frame) }
                guard let display = LiveStateWindowPlacement.mainDisplayFrame else {
                    throw LiveStateFailure("No main display is available for the region of the state \(description.name).")
                }
                guard frame.width >= 1, frame.height >= 1, display.contains(frame) else {
                    throw LiveStateFailure("The region \(NSStringFromRect(frame)) of the state \(description.name) does not lie inside the main display \(NSStringFromRect(display)).")
                }
                regionFrame = frame
                regionOrigin = CGPoint(x: frame.minX - display.minX, y: display.maxY - frame.maxY)
            }
            try verifyDisplaySafety()
            let state = PresentedLiveState(description: description, presentation: presentation, stack: stack,
                                           regionFrame: regionFrame, regionOrigin: regionOrigin, frontWindow: front, menuWindow: menuWindow)
            LiveStateLog.event("live_state_built", [
                "state": description.name, "windowNumbers": stack.map(\.windowNumber), "region": regionFrame != nil,
                "windowClasses": stack.map { String(describing: type(of: $0)) },
                "levels": stack.map(\.level.rawValue), "milliseconds": LiveStateLog.milliseconds(since: begun),
            ])
            return state
        } catch {
            if let host = menuPresenter.hostWindow, stack.contains(where: { $0 === host }) { menuPresenter.close(reason: "build_failed") }
            LiveStateWindowPlacement.tearDown(stack)
            presentation.tearDown?()
            LiveStateLog.event("live_state_build_failed", ["state": description.name, "reason": error.localizedDescription,
                                                           "removedWindowNumbers": stack.map(\.windowNumber),
                                                           "milliseconds": LiveStateLog.milliseconds(since: begun)])
            throw error
        }
    }

    private func announce(_ state: PresentedLiveState, milliseconds: Double) {
        let front = state.frontWindow
        var fields: [String: Any] = [
            "event": "live_state_ready", "state": state.description.name, "windowNumber": front.windowNumber,
            "windowWidth": Double(state.size.width), "windowHeight": Double(state.size.height), "backingScale": Double(front.backingScaleFactor),
        ]
        if state.regionFrame != nil {
            fields["regionWindowNumbers"] = state.stack.map(\.windowNumber)
            fields["regionX"] = Double(state.regionOrigin.x)
            fields["regionY"] = Double(state.regionOrigin.y)
        }
        LiveStateOutput.write(fields)
        presentedStateNames.append(state.description.name)
        keyTarget = nil
        mouseTarget = nil
        isMouseDownBlocked = false
        var logged = fields
        logged.removeValue(forKey: "event")
        logged["milliseconds"] = milliseconds
        LiveStateLog.event("live_state_presented", logged)
    }

    private func replace(with name: String, record: LiveStateCommandRecord) async {
        var record = record
        record.fields["state"] = name
        let description: LiveStateDescription
        do {
            description = try resolve(name)
        } catch {
            reject(error.localizedDescription, record: record)
            return
        }
        guard let previous = presented else { return }
        releaseMouse()
        let previousAppearance = NSApp.appearance
        let restoration = application.sharedStateRestoration()
        do {
            let next = try await build(description)
            if let host = menuPresenter.hostWindow, previous.stack.contains(where: { $0 === host }) { menuPresenter.close(reason: "present") }
            isPointerGestureConsumedByMenu = false
            LiveStateWindowPlacement.tearDown(previous.stack)
            previous.presentation.tearDown?()
            presented = next
            announce(next, milliseconds: LiveStateLog.milliseconds(since: record.received))
            record.fields["previousState"] = previous.description.name
            finishCommand(record, outcome: "presented")
        } catch {
            NSApp.appearance = previousAppearance
            restoration?()
            record.fields["keptState"] = previous.description.name
            reject(error.localizedDescription, record: record)
        }
    }

    private func reject(_ reason: String, record: LiveStateCommandRecord) {
        LiveStateOutput.write(["event": "live_state_failed", "reason": reason])
        var record = record
        record.fields["reason"] = reason
        finishCommand(record, outcome: "rejected")
    }

    private func startReadingCommands() {
        let session = self
        Thread.detachNewThread {
            while let line = readLine() {
                DispatchQueue.main.async { MainActor.assumeIsolated { session.receive(line) } }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { session.receiveEndOfInput() } }
        }
    }

    private func receive(_ line: String) {
        guard !isFinishing else { return }
        if isPresenting {
            queuedLines.append(line)
            return
        }
        perform(line)
    }

    private func receiveEndOfInput() {
        LiveStateLog.event("standard_input_ended")
        receive("quit")
    }

    private func drainQueuedLines() {
        while !isPresenting, !isFinishing, !queuedLines.isEmpty {
            perform(queuedLines.removeFirst())
        }
    }

    private func perform(_ line: String) {
        switch LiveStateCommand.parse(line) {
        case .empty:
            return
        case .ignored(let reason):
            var record = LiveStateCommandRecord(word: line.split(separator: " ").first.map(String.init) ?? "")
            record.fields["line"] = line
            record.fields["reason"] = reason
            finishCommand(record, outcome: "ignored")
        case .rejectedPresent(let reason):
            var record = LiveStateCommandRecord(word: "present")
            record.fields["line"] = line
            reject(reason, record: record)
        case .command(let command):
            LiveStateOutput.write(["event": "input_handled", "command": command.word, "handledUptime": ProcessInfo.processInfo.systemUptime])
            execute(command, record: LiveStateCommandRecord(word: command.word))
        }
    }

    private func execute(_ command: LiveStateCommand, record: LiveStateCommandRecord) {
        switch command {
        case .quit:
            quit(record: record)
        case .present(let name):
            isPresenting = true
            Task { @MainActor in
                await replace(with: name, record: record)
                isPresenting = false
                drainQueuedLines()
            }
        case .click(let x, let y):
            click(x: x, y: y, record: record)
        case .mouseDown(let x, let y):
            mouse(.leftMouseDown, x: x, y: y, record: record)
        case .mouseDragged(let x, let y):
            mouse(.leftMouseDragged, x: x, y: y, record: record)
        case .mouseUp(let x, let y):
            mouse(.leftMouseUp, x: x, y: y, record: record)
        case .mouseMoved(let x, let y):
            mouseMoved(x: x, y: y, record: record)
        case .rightClick(let x, let y):
            rightClick(x: x, y: y, record: record)
        case .scroll(let x, let y, let deltaX, let deltaY):
            scroll(x: x, y: y, deltaX: deltaX, deltaY: deltaY, record: record)
        case .key(let name, let modifiers):
            key(name, modifiers: modifiers, record: record)
        case .type(let text):
            typeText(text, record: record)
        }
    }

    private func finishCommand(_ record: LiveStateCommandRecord, outcome: String) {
        commandOutcomes["\(record.word):\(outcome)", default: 0] += 1
        var fields = record.fields
        fields["command"] = record.word
        fields["outcome"] = outcome
        fields["milliseconds"] = LiveStateLog.milliseconds(since: record.received)
        fields["presentedState"] = presented?.description.name ?? NSNull()
        LiveStateLog.event("live_state_command", fields)
    }

    private func acknowledge(_ record: LiveStateCommandRecord) {
        keepStageOrder()
        LiveStateOutput.write(["event": "input_replayed", "command": record.word])
        finishCommand(record, outcome: "replayed")
        checkSafety()
    }

    private func acknowledgePendingMouseDown() {
        guard let pending = pendingMouseDown else { return }
        pendingMouseDown = nil
        acknowledge(pending)
    }

    private func ignore(_ record: LiveStateCommandRecord, reason: String) {
        var record = record
        record.fields["reason"] = reason
        finishCommand(record, outcome: "ignored")
    }

    private func target(_ record: inout LiveStateCommandRecord, x: Double, y: Double) -> NSWindow? {
        record.fields["x"] = x
        record.fields["y"] = y
        guard let state = presented else { return nil }
        guard state.contains(x: x, y: y) else {
            ignore(record, reason: "The point lies outside the \(state.size.width) by \(state.size.height) point \(state.regionFrame == nil ? "window frame" : "region").")
            return nil
        }
        guard let window = state.window(at: state.screenPoint(x: x, y: y)) else {
            ignore(record, reason: "No input window of the state lies under the point.")
            return nil
        }
        record.fields["targetWindowNumber"] = window.windowNumber
        return window
    }

    private func acknowledgeBlocked(_ record: LiveStateCommandRecord) {
        var record = record
        record.fields["blockedByWindowNumber"] = presented?.modalWindow?.windowNumber ?? NSNull()
        acknowledgePendingMouseDown()
        LiveStateOutput.write(["event": "input_replayed", "command": record.word])
        finishCommand(record, outcome: "blocked_by_alert")
        checkSafety()
    }

    private func isBlockedByAlert(_ window: NSWindow) -> Bool {
        guard let modal = presented?.modalWindow else { return false }
        return modal !== window
    }

    private func menuPoint(_ record: inout LiveStateCommandRecord, x: Double, y: Double) -> NSPoint? {
        record.fields["x"] = x
        record.fields["y"] = y
        guard let state = presented else { return nil }
        guard state.contains(x: x, y: y) || record.word != "mouse_down" && record.word != "click" else {
            ignore(record, reason: "The point lies outside the \(state.size.width) by \(state.size.height) point \(state.regionFrame == nil ? "window frame" : "region").")
            return nil
        }
        return state.screenPoint(x: x, y: y)
    }

    private func acknowledgeMenu(_ record: LiveStateCommandRecord, outcome: String) {
        var record = record
        record.fields["menuOutcome"] = outcome
        acknowledgePendingMouseDown()
        keepStageOrder()
        LiveStateOutput.write(["event": "input_replayed", "command": record.word])
        finishCommand(record, outcome: "menu")
        checkSafety()
    }

    private func mouseMoved(x: Double, y: Double, record: LiveStateCommandRecord) {
        var record = record
        if menuPresenter.isShowing {
            guard let point = menuPoint(&record, x: x, y: y) else { return }
            return acknowledgeMenu(record, outcome: menuPresenter.pointerMoved(to: point, dragging: false).rawValue)
        }
        guard let window = target(&record, x: x, y: y) else { return }
        if isBlockedByAlert(window) { return acknowledgeBlocked(record) }
        guard let event = mouseEvent(.mouseMoved, x: x, y: y, in: window) else {
            return fail("NSEvent could not create the mouse moved event at \(x), \(y).")
        }
        acknowledgePendingMouseDown()
        window.sendEvent(event)
        record.fields["dispatch"] = "sent"
        acknowledge(record)
    }

    private func rightClick(x: Double, y: Double, record: LiveStateCommandRecord) {
        var record = record
        if menuPresenter.isShowing {
            guard let point = menuPoint(&record, x: x, y: y) else { return }
            return acknowledgeMenu(record, outcome: menuPresenter.click(at: point).rawValue)
        }
        guard let window = target(&record, x: x, y: y) else { return }
        if isBlockedByAlert(window) { return acknowledgeBlocked(record) }
        guard let down = mouseEvent(.rightMouseDown, x: x, y: y, in: window), let up = mouseEvent(.rightMouseUp, x: x, y: y, in: window) else {
            return fail("NSEvent could not create the mouse events for a right click at \(x), \(y).")
        }
        acknowledgePendingMouseDown()
        keyTarget = window
        NSApp.postEvent(up, atStart: false)
        NSApp.sendEvent(down)
        record.fields["dispatch"] = "sent"
        acknowledge(record)
    }

    private func mouseEvent(_ type: NSEvent.EventType, x: Double, y: Double, in window: NSWindow) -> NSEvent? {
        guard let state = presented else { return nil }
        let point = state.screenPoint(x: x, y: y)
        eventNumber += 1
        return NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY),
                                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                  context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseUp || type == .rightMouseUp || type == .mouseMoved ? 0 : 1)
    }

    private func click(x: Double, y: Double, record: LiveStateCommandRecord) {
        var record = record
        if menuPresenter.isShowing {
            guard let point = menuPoint(&record, x: x, y: y) else { return }
            return acknowledgeMenu(record, outcome: menuPresenter.click(at: point).rawValue)
        }
        guard let window = target(&record, x: x, y: y) else { return }
        isMouseDownBlocked = false
        if isBlockedByAlert(window) { return acknowledgeBlocked(record) }
        guard let down = mouseEvent(.leftMouseDown, x: x, y: y, in: window), let up = mouseEvent(.leftMouseUp, x: x, y: y, in: window) else {
            return fail("NSEvent could not create the mouse events for a click at \(x), \(y).")
        }
        acknowledgePendingMouseDown()
        keyTarget = window
        if isDispatchingMouseDown {
            NSApp.postEvent(down, atStart: false)
            NSApp.postEvent(up, atStart: false)
            record.fields["dispatch"] = "posted"
        } else {
            NSApp.postEvent(up, atStart: false)
            NSApp.sendEvent(down)
            record.fields["dispatch"] = "sent"
        }
        isMouseDown = false
        mouseTarget = nil
        acknowledge(record)
    }

    private func mouse(_ type: NSEvent.EventType, x: Double, y: Double, record: LiveStateCommandRecord) {
        var record = record
        if isPointerGestureConsumedByMenu, type != .leftMouseDown {
            record.fields["x"] = x
            record.fields["y"] = y
            if type == .leftMouseUp { isPointerGestureConsumedByMenu = false }
            return acknowledgeMenu(record, outcome: "consumed_after_close")
        }
        if menuPresenter.isShowing {
            guard let point = menuPoint(&record, x: x, y: y) else { return }
            let outcome: LiveStateMenuPointerOutcome
            switch type {
            case .leftMouseDown:
                outcome = menuPresenter.pointerDown(at: point)
                isPointerGestureConsumedByMenu = outcome == .closedOutside
            case .leftMouseDragged:
                outcome = menuPresenter.pointerMoved(to: point, dragging: true)
            default:
                if isMouseDown, let window = mouseTarget, let up = mouseEvent(.leftMouseUp, x: x, y: y, in: window) {
                    if isDispatchingMouseDown { NSApp.postEvent(up, atStart: false) } else { NSApp.sendEvent(up) }
                    record.fields["openingGestureEndedInWindowNumber"] = window.windowNumber
                }
                outcome = menuPresenter.pointerUp(at: point)
                isMouseDown = false
                mouseTarget = nil
                menuPresenter.isPointerDown = false
            }
            return acknowledgeMenu(record, outcome: outcome.rawValue)
        }
        let window: NSWindow
        if type == .leftMouseDown {
            guard let under = target(&record, x: x, y: y) else { return }
            isMouseDownBlocked = isBlockedByAlert(under)
            if isMouseDownBlocked { return acknowledgeBlocked(record) }
            window = under
            mouseTarget = under
            keyTarget = under
        } else {
            record.fields["x"] = x
            record.fields["y"] = y
            if isMouseDownBlocked {
                if type == .leftMouseUp { isMouseDownBlocked = false }
                return acknowledgeBlocked(record)
            }
            guard let tracking = mouseTarget ?? presented?.frontWindow else { return ignore(record, reason: "No window is presented.") }
            window = tracking
            record.fields["targetWindowNumber"] = window.windowNumber
        }
        guard let event = mouseEvent(type, x: x, y: y, in: window) else {
            return fail("NSEvent could not create the \(record.word) event at \(x), \(y).")
        }
        acknowledgePendingMouseDown()
        if type == .leftMouseDown {
            isMouseDown = true
            if isDispatchingMouseDown {
                NSApp.postEvent(event, atStart: false)
                record.fields["dispatch"] = "posted"
                return acknowledge(record)
            }
            isDispatchingMouseDown = true
            record.fields["dispatch"] = "sent"
            menuPresenter.isPointerDown = true
            menuPresenter.pointerDownScreenPoint = presented?.screenPoint(x: x, y: y)
            pendingMouseDown = record
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated { acknowledgePendingMouseDown() }
            }
            NSApp.sendEvent(event)
            isDispatchingMouseDown = false
            acknowledgePendingMouseDown()
            return
        }
        if type == .leftMouseUp {
            isMouseDown = false
            mouseTarget = nil
            menuPresenter.isPointerDown = false
        }
        if isDispatchingMouseDown {
            NSApp.postEvent(event, atStart: false)
            record.fields["dispatch"] = "posted"
        } else {
            NSApp.sendEvent(event)
            record.fields["dispatch"] = "sent"
        }
        acknowledge(record)
    }

    private func releaseMouse() {
        guard isMouseDown, let window = mouseTarget ?? presented?.frontWindow, let up = mouseEvent(.leftMouseUp, x: 0, y: 0, in: window) else { return }
        isMouseDown = false
        mouseTarget = nil
        if isDispatchingMouseDown { NSApp.postEvent(up, atStart: false) } else { NSApp.sendEvent(up) }
        LiveStateLog.event("mouse_released", ["windowNumber": window.windowNumber])
    }

    private func scroll(x: Double, y: Double, deltaX: Double, deltaY: Double, record: LiveStateCommandRecord) {
        var record = record
        if menuPresenter.isShowing {
            guard let point = menuPoint(&record, x: x, y: y) else { return }
            menuPresenter.scroll(at: point, deltaY: deltaY)
            return acknowledgeMenu(record, outcome: "scrolled")
        }
        guard let window = target(&record, x: x, y: y) else { return }
        if isBlockedByAlert(window) { return acknowledgeBlocked(record) }
        record.fields["deltaX"] = deltaX
        record.fields["deltaY"] = deltaY
        guard let pointer = mouseEvent(.mouseMoved, x: x, y: y, in: window), let source = pointer.cgEvent else {
            return fail("NSEvent could not create the pointer event for a scroll at \(x), \(y).")
        }
        source.type = .scrollWheel
        source.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        for (vertical, delta) in [(true, deltaY), (false, deltaX)] {
            let whole = Int64(delta.rounded())
            source.setIntegerValueField(vertical ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2, value: whole)
            source.setIntegerValueField(vertical ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2, value: whole)
            source.setDoubleValueField(vertical ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2, value: delta)
        }
        guard let event = NSEvent(cgEvent: source), event.type == .scrollWheel, event.window === window else {
            return fail("NSEvent could not convert the pointer event into a scroll wheel event for window \(window.windowNumber).")
        }
        acknowledgePendingMouseDown()
        NSApp.sendEvent(event)
        record.fields["dispatch"] = "sent"
        acknowledge(record)
    }

    private func key(_ name: String, modifiers: [LiveStateModifier], record: LiveStateCommandRecord) {
        var record = record
        record.fields["key"] = name
        record.fields["modifiers"] = modifiers.map(\.rawValue)
        guard let stroke = LiveStateKeyStroke.named(name, modifiers: modifiers) else {
            return ignore(record, reason: "The key \(name.debugDescription) has no key stroke.")
        }
        if menuPresenter.isShowing { return acknowledgeMenu(record, outcome: menuPresenter.key(name)) }
        guard send(stroke, record: &record) else { return }
        acknowledge(record)
    }

    private func typeText(_ text: String, record: LiveStateCommandRecord) {
        var record = record
        record.fields["characters"] = text.count
        if menuPresenter.isShowing { return acknowledgeMenu(record, outcome: menuPresenter.typeSelect(text)) }
        for character in text {
            guard send(LiveStateKeyStroke.typed(character), record: &record) else { return }
        }
        acknowledge(record)
    }

    private func send(_ stroke: LiveStateKeyStroke, record: inout LiveStateCommandRecord) -> Bool {
        guard let state = presented, let window = state.modalWindow ?? keyTarget.flatMap({ $0.isVisible ? $0 : nil }) ?? state.inputWindows.first else {
            ignore(record, reason: "No window is presented.")
            return false
        }
        record.fields["targetWindowNumber"] = window.windowNumber
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: stroke.modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                             windowNumber: window.windowNumber, context: nil, characters: stroke.characters,
                             charactersIgnoringModifiers: stroke.charactersIgnoringModifiers, isARepeat: false, keyCode: stroke.keyCode)
        }
        guard let down = event(.keyDown), let up = event(.keyUp) else {
            fail("NSEvent could not create the key events for \(stroke.characters.debugDescription).")
            return false
        }
        acknowledgePendingMouseDown()
        if stroke.modifiers.isDisjoint(with: [.command, .control]) || !window.performKeyEquivalent(with: down) {
            window.sendEvent(down)
        }
        window.sendEvent(up)
        return true
    }

    private func keepStageOrder() {
        guard let state = presented, state.regionFrame != nil else { return }
        let stack = state.visibleStack
        let expected = stack.map(\.windowNumber)
        let found = LiveStateWindowPlacement.windowServerOrder(of: stack)
        guard found != expected else { return }
        LiveStateWindowPlacement.restoreOrder(of: stack)
        LiveStateLog.event("stage_order_restored", ["found": found, "expected": expected])
    }

    private func verifyDisplaySafety() throws {
        let safety = LiveStateDisplaySafety()
        safetySummary.record(safety)
        if safety != lastSafety {
            lastSafety = safety
            var fields = safety.fields
            fields["checks"] = safetySummary.checks
            LiveStateLog.event("display_safety", fields)
        }
        let failures = safety.failures
        guard failures.isEmpty else {
            throw LiveStateFailure("The display safety check failed: \(failures.joined(separator: "; ")).")
        }
    }

    private func checkSafety() {
        guard !isFinishing else { return }
        keepStageOrder()
        do {
            try verifyDisplaySafety()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func quit(record: LiveStateCommandRecord) {
        guard !isFinishing else { return }
        releaseMouse()
        finishCommand(record, outcome: "quit")
        finish(status: 0, reason: nil)
    }

    private func fail(_ reason: String) {
        guard !isFinishing else { return }
        LiveStateOutput.write(["event": "live_state_failed", "reason": reason])
        finish(status: 1, reason: reason)
    }

    private func finish(status: Int32, reason: String?) -> Never {
        isFinishing = true
        menuPresenter.close(reason: "quit")
        safetyTimer?.invalidate()
        if let state = presented {
            LiveStateWindowPlacement.tearDown(state.stack)
            state.presentation.tearDown?()
        }
        presented = nil
        for window in NSApp.windows where window.isVisible { window.orderOut(nil) }
        LiveStateLog.event("display_safety_checks", safetySummary.fields)
        if isIsolationBegun {
            application.endFixtureIsolation()
            LiveStateLog.event("fixture_isolation_ended")
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        LiveStateLog.event("live_state_run_finished", [
            "exitStatus": Int(status), "reason": reason ?? NSNull(), "milliseconds": LiveStateLog.milliseconds(since: started),
            "presentedStates": presentedStateNames, "commandOutcomes": commandOutcomes,
        ])
        exit(status)
    }
}
