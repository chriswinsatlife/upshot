import AppKit

@MainActor
public protocol LiveStateApplication: AnyObject {
    func beginFixtureIsolation() async throws
    func liveStateCatalog() async throws -> LiveStateCatalog
    func makeLiveStatePresentation(for state: LiveStateDescription) async throws -> LiveStatePresentation
    func sharedStateRestoration() -> (@MainActor () -> Void)?
    func endFixtureIsolation()
}

extension LiveStateApplication {
    public func beginFixtureIsolation() async throws {}
    public func sharedStateRestoration() -> (@MainActor () -> Void)? { nil }
    public func endFixtureIsolation() {}
}

public enum LiveStateAppearance: String, Sendable, CaseIterable {
    case light
    case dark

    public var appearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

public struct LiveStateDescription: Sendable, Equatable {
    public let name: String
    public let baseState: String
    public let appearance: LiveStateAppearance
    public let sourceFile: String
    public let sourceLine: Int

    public init(name: String, baseState: String, appearance: LiveStateAppearance, sourceFile: String, sourceLine: Int) {
        self.name = name
        self.baseState = baseState
        self.appearance = appearance
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }
}

public struct UnsupportedLiveState: Sendable, Equatable {
    public let name: String
    public let reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }
}

public struct LiveStateCatalog: Sendable, Equatable {
    public let states: [LiveStateDescription]
    public let unsupported: [UnsupportedLiveState]

    public init(states: [LiveStateDescription], unsupported: [UnsupportedLiveState] = []) {
        self.states = states
        self.unsupported = unsupported
    }

    func validationFailures() -> [String] {
        let names = states.map(\.name) + unsupported.map(\.name)
        var failures: [String] = []
        let duplicates = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        if !duplicates.isEmpty { failures.append("The catalog names these states more than once: \(duplicates.joined(separator: ", ")).") }
        let malformed = names.filter { $0.isEmpty || $0.hasPrefix("--") || $0.contains(where: \.isWhitespace) }
        if !malformed.isEmpty { failures.append("These state names are empty, start with --, or contain whitespace: \(malformed.map(\.debugDescription).joined(separator: ", ")).") }
        return failures
    }
}

@MainActor
public struct LiveStatePresentation {
    public var windows: [NSWindow]
    public var backdropWindow: NSWindow?
    public var regionFrame: CGRect?
    public var settleDuration: Duration
    public var tearDown: (@MainActor () -> Void)?
    var modalWindow: NSWindow?
    public var menuMargin = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    public var openInitialMenu: (@MainActor () -> Void)?

    var hasMenuMargin: Bool { menuMargin.top > 0 || menuMargin.left > 0 || menuMargin.bottom > 0 || menuMargin.right > 0 }

    public init(window: NSWindow, settleDuration: Duration = .milliseconds(100), tearDown: (@MainActor () -> Void)? = nil) {
        self.windows = [window]
        self.backdropWindow = nil
        self.regionFrame = nil
        self.settleDuration = settleDuration
        self.tearDown = tearDown
    }

    public init(regionWindows windows: [NSWindow], backdropWindow: NSWindow? = nil, regionFrame: CGRect? = nil,
                settleDuration: Duration = .milliseconds(100), tearDown: (@MainActor () -> Void)? = nil) {
        self.windows = windows
        self.backdropWindow = backdropWindow
        self.regionFrame = regionFrame
        self.settleDuration = settleDuration
        self.tearDown = tearDown
    }

    var presentsRegion: Bool { windows.count != 1 || backdropWindow != nil || regionFrame != nil || hasMenuMargin }

    var stackWindows: [NSWindow] { (backdropWindow.map { [$0] } ?? []) + windows }
}

public struct LiveStateFailure: LocalizedError, Sendable {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var errorDescription: String? { reason }
}
