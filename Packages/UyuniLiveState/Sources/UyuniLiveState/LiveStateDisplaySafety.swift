import AppKit

struct LiveStateWindowSafety: Equatable, Sendable {
    let className: String
    let windowNumber: Int
    let level: Int
    let isVisible: Bool
    let serverLayer: Int?
    let isOnscreen: Bool

    @MainActor
    init(_ window: NSWindow) {
        className = String(describing: type(of: window))
        windowNumber = window.windowNumber
        level = window.level.rawValue
        isVisible = window.isVisible
        let record = LiveStateWindowPlacement.serverRecord(for: window)
        serverLayer = record?.layer
        isOnscreen = record?.isOnscreen ?? false
    }

    var failures: [String] {
        let desktopLevel = LiveStateWindowPlacement.desktopLevel
        var failures: [String] = []
        if isVisible, level >= desktopLevel {
            failures.append("window \(windowNumber) \(className) is visible at level \(level), which is not below the desktop level \(desktopLevel)")
        }
        if isOnscreen, let serverLayer, serverLayer >= desktopLevel {
            failures.append("window \(windowNumber) \(className) is on screen at window-server layer \(serverLayer), which is not below the desktop layer \(desktopLevel)")
        }
        return failures
    }

    var fields: [String: Any] {
        ["class": className, "windowNumber": windowNumber, "level": level, "visible": isVisible,
         "serverLayer": serverLayer ?? NSNull(), "onscreen": isOnscreen]
    }
}

struct LiveStateDisplaySafety: Equatable, Sendable {
    static let prohibitedPolicy = NSApplication.ActivationPolicy.prohibited.rawValue
    static let policyRereadLimit = 25
    static let policyRereadMicroseconds: useconds_t = 1000

    let cachedActivationPolicy: Int
    let activationPolicy: Int
    let policyRereads: Int
    let isActive: Bool
    let windows: [LiveStateWindowSafety]

    @MainActor
    init() {
        cachedActivationPolicy = NSApp.activationPolicy().rawValue
        var policy = cachedActivationPolicy
        var rereads = 0
        while policy != Self.prohibitedPolicy, rereads < Self.policyRereadLimit {
            usleep(Self.policyRereadMicroseconds)
            rereads += 1
            policy = NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)?.activationPolicy.rawValue ?? policy
        }
        activationPolicy = policy
        policyRereads = rereads
        isActive = NSApp.isActive
        windows = NSApp.windows.map(LiveStateWindowSafety.init)
    }

    var failures: [String] {
        var failures: [String] = []
        if activationPolicy != Self.prohibitedPolicy {
            failures.append("the activation policy is \(activationPolicy) after \(policyRereads) rereads and was \(cachedActivationPolicy) in NSApp, which is not prohibited \(Self.prohibitedPolicy)")
        }
        if isActive { failures.append("the app is active") }
        return failures + windows.flatMap(\.failures)
    }

    var fields: [String: Any] {
        ["policy": activationPolicy, "cachedPolicy": cachedActivationPolicy, "policyRereads": policyRereads,
         "active": isActive, "windows": windows.map(\.fields)]
    }
}

@MainActor
struct LiveStateSafetySummary {
    private(set) var checks = 0
    private(set) var highestVisibleWindowLevel: Int?
    private(set) var highestOnscreenServerLayer: Int?
    private(set) var windowNumbers: Set<Int> = []
    private(set) var policyRereadPasses = 0

    mutating func record(_ safety: LiveStateDisplaySafety) {
        checks += 1
        if safety.policyRereads > 0 { policyRereadPasses += 1 }
        for window in safety.windows {
            windowNumbers.insert(window.windowNumber)
            if window.isVisible { highestVisibleWindowLevel = max(highestVisibleWindowLevel ?? window.level, window.level) }
            if window.isOnscreen, let layer = window.serverLayer { highestOnscreenServerLayer = max(highestOnscreenServerLayer ?? layer, layer) }
        }
    }

    var fields: [String: Any] {
        ["checks": checks, "desktopLevel": LiveStateWindowPlacement.desktopLevel,
         "highestVisibleWindowLevel": highestVisibleWindowLevel ?? NSNull(),
         "highestOnscreenServerLayer": highestOnscreenServerLayer ?? NSNull(),
         "windowsObserved": windowNumbers.count, "policyRereadPasses": policyRereadPasses]
    }
}
