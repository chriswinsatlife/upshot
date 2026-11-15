import AppKit
import ObjectiveC

open class LiveStateWindow: NSWindow {
    open override var canBecomeKey: Bool { false }
    open override var canBecomeMain: Bool { false }
    open override var isKeyWindow: Bool { true }
    open override var isMainWindow: Bool { true }
    @objc open var hasKeyAppearance: Bool { true }
    @objc open var hasMainAppearance: Bool { true }
    @objc open func _hasKeyAppearance() -> Bool { true }
    @objc open func _hasMainAppearance() -> Bool { true }
    @objc open func _hasActiveAppearance() -> Bool { true }
    @objc open func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc open func _hasActiveAppearanceForStandardWindowButton(_ button: Int) -> Bool { true }
}

open class LiveStatePanel: NSPanel {
    open override var canBecomeKey: Bool { false }
    open override var canBecomeMain: Bool { false }
    open override var isKeyWindow: Bool { true }
    @objc open var hasKeyAppearance: Bool { true }
    @objc open func _hasKeyAppearance() -> Bool { true }
    @objc open func _hasActiveAppearance() -> Bool { true }
    @objc open func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

@MainActor
enum LiveStateWindowPlacement {
    nonisolated static let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
    static var belowDesktopLevel: NSWindow.Level { NSWindow.Level(rawValue: desktopLevel - 1) }
    private static var installedGuards: [String] = []

    static func installWindowLevelGuards() -> [String] {
        let exchanges: [(name: String, original: Selector, replacement: Selector)] = [
            ("addChildWindow:ordered:", #selector(NSWindow.addChildWindow(_:ordered:)), #selector(NSWindow.uyuniLiveStateAddChildWindow(_:ordered:))),
            ("orderWindow:relativeTo:", #selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.uyuniLiveStateOrder(_:relativeTo:))),
            ("setLevel:", #selector(setter: NSWindow.level), #selector(NSWindow.uyuniLiveStateSetLevel(_:))),
            ("orderFrontRegardless", #selector(NSWindow.orderFrontRegardless), #selector(NSWindow.uyuniLiveStateOrderFrontRegardless)),
        ]
        var missing: [String] = []
        for exchange in exchanges where !installedGuards.contains(exchange.name) {
            guard let originalMethod = class_getInstanceMethod(NSWindow.self, exchange.original),
                  let replacementMethod = class_getInstanceMethod(NSWindow.self, exchange.replacement) else {
                missing.append(exchange.name)
                continue
            }
            method_exchangeImplementations(originalMethod, replacementMethod)
            installedGuards.append(exchange.name)
        }
        var unavailable: [[String: Any]] = []
        let privateName = "_doOrderWindow:"
        if !installedGuards.contains(privateName) {
            if let originalMethod = class_getInstanceMethod(NSWindow.self, NSSelectorFromString(privateName)),
               let replacementMethod = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.uyuniLiveStateDoOrderWindow(_:))) {
                let found = method_getTypeEncoding(originalMethod).map { String(cString: $0) } ?? ""
                if found == privateOrderingEncoding {
                    method_exchangeImplementations(originalMethod, replacementMethod)
                    installedGuards.append(privateName)
                } else {
                    unavailable.append(["method": "-[NSWindow \(privateName)]", "reason": "type encoding \(found) differs from \(privateOrderingEncoding)"])
                }
            } else {
                unavailable.append(["method": "-[NSWindow \(privateName)]", "reason": "missing"])
            }
        }
        if !unavailable.isEmpty { LiveStateLog.event("private_window_guards_unavailable", ["methods": unavailable]) }
        LiveStateLog.event("window_level_guards_installed", ["methods": installedGuards, "missing": missing])
        return missing
    }

    static let privateOrderingEncoding = "v24@0:8@16"

    static func clampedLevel(_ level: NSWindow.Level, for window: NSWindow) -> NSWindow.Level {
        guard level.rawValue >= desktopLevel else { return level }
        LiveStateLog.event("window_level_clamped", ["class": String(describing: type(of: window)), "windowNumber": window.windowNumber,
                                                    "requestedLevel": level.rawValue, "level": belowDesktopLevel.rawValue])
        return belowDesktopLevel
    }

    static func lowerBeforeOrderingIn(_ window: NSWindow) {
        let previousLevel = window.level.rawValue
        guard previousLevel >= desktopLevel || !window.ignoresMouseEvents else { return }
        if previousLevel >= desktopLevel { window.level = belowDesktopLevel }
        window.ignoresMouseEvents = true
        LiveStateLog.event("window_lowered_before_ordering_in", ["class": String(describing: type(of: window)), "windowNumber": window.windowNumber,
                                                                "previousLevel": previousLevel, "level": window.level.rawValue])
    }

    static func lower(_ child: NSWindow, beneath parent: NSWindow) {
        let previousLevel = child.level.rawValue
        if previousLevel >= desktopLevel {
            child.level = parent.level.rawValue < desktopLevel ? parent.level : belowDesktopLevel
        }
        child.ignoresMouseEvents = true
        child.hidesOnDeactivate = false
        LiveStateLog.event("child_window_lowered", [
            "childClass": String(describing: type(of: child)), "childWindowNumber": child.windowNumber,
            "parentWindowNumber": parent.windowNumber, "previousLevel": previousLevel, "level": child.level.rawValue,
        ])
    }

    static func prepare(_ window: NSWindow, appearance: LiveStateAppearance) throws {
        if window.isVisible, window.level.rawValue >= desktopLevel {
            throw LiveStateFailure("Window \(window.windowNumber) of class \(type(of: window)) was already ordered in at level \(window.level.rawValue) when the app handed it to the live state package; build windows without ordering them in.")
        }
        if window.level.rawValue >= desktopLevel { window.level = belowDesktopLevel }
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.sharingType = .readOnly
        window.appearance = NSAppearance(named: appearance.appearanceName)
        for child in window.childWindows ?? [] { lower(child, beneath: window) }
    }

    static func orderIn(_ stack: [NSWindow]) {
        for (index, window) in stack.enumerated() {
            if index == 0 {
                window.orderBack(nil)
            } else {
                window.order(.above, relativeTo: stack[index - 1].windowNumber)
            }
        }
    }

    static func windowServerOrder(of stack: [NSWindow]) -> [Int] {
        let numbers = Set(stack.map(\.windowNumber))
        let listed = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return listed.compactMap { $0[kCGWindowNumber as String] as? Int }.filter(numbers.contains).reversed()
    }

    static func restoreOrder(of stack: [NSWindow]) {
        for (lower, upper) in zip(stack, stack.dropFirst()) {
            upper.order(.above, relativeTo: lower.windowNumber)
        }
    }

    static func serverRecord(for window: NSWindow) -> (layer: Int, isOnscreen: Bool)? {
        guard window.windowNumber > 0,
              let information = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]])?.first,
              let layer = information[kCGWindowLayer as String] as? Int else { return nil }
        return (layer, information[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }

    static let orderedInWaitSeconds = 2
    static let orderedInPollMilliseconds = 10

    static func requireOrderedInBelowDesktop(_ window: NSWindow) async throws -> Double {
        let begun = ContinuousClock.now
        let deadline = begun + .seconds(orderedInWaitSeconds)
        while true {
            if let record = serverRecord(for: window), record.isOnscreen {
                guard record.layer < desktopLevel else {
                    throw LiveStateFailure("Window \(window.windowNumber) is at window-server layer \(record.layer), which is not below the desktop layer \(desktopLevel).")
                }
                return LiveStateLog.milliseconds(since: begun)
            }
            guard ContinuousClock.now < deadline else { break }
            try await Task.sleep(for: .milliseconds(orderedInPollMilliseconds))
        }
        throw LiveStateFailure("Window \(window.windowNumber) was not ordered in at the window server within \(orderedInWaitSeconds) seconds.")
    }

    static func tearDown(_ stack: [NSWindow]) {
        for window in stack.reversed() {
            window.orderOut(nil)
            window.close()
        }
    }

    static var mainDisplayFrame: CGRect? {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame
    }
}

extension NSWindow {
    @objc(uyuniLiveStateAddChildWindow:ordered:)
    dynamic func uyuniLiveStateAddChildWindow(_ child: NSWindow, ordered place: NSWindow.OrderingMode) {
        LiveStateWindowPlacement.lower(child, beneath: self)
        uyuniLiveStateAddChildWindow(child, ordered: place)
    }

    @objc(uyuniLiveStateOrderWindow:relativeTo:)
    dynamic func uyuniLiveStateOrder(_ place: NSWindow.OrderingMode, relativeTo otherWindow: Int) {
        if place != .out { LiveStateWindowPlacement.lowerBeforeOrderingIn(self) }
        uyuniLiveStateOrder(place, relativeTo: otherWindow)
    }

    @objc(uyuniLiveStateOrderFrontRegardless)
    dynamic func uyuniLiveStateOrderFrontRegardless() {
        LiveStateWindowPlacement.lowerBeforeOrderingIn(self)
        uyuniLiveStateOrderFrontRegardless()
    }

    @objc(uyuniLiveStateDoOrderWindow:)
    dynamic func uyuniLiveStateDoOrderWindow(_ options: AnyObject?) {
        LiveStateWindowPlacement.lowerBeforeOrderingIn(self)
        uyuniLiveStateDoOrderWindow(options)
    }

    @objc(uyuniLiveStateSetLevel:)
    dynamic func uyuniLiveStateSetLevel(_ level: NSWindow.Level) {
        uyuniLiveStateSetLevel(LiveStateWindowPlacement.clampedLevel(level, for: self))
    }
}
