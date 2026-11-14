import Foundation

nonisolated enum UpshotStorage {
    static let isPresentingLiveState = CommandLine.arguments.dropFirst().first == "--present-live-state"
    static let isListingLiveStates = CommandLine.arguments.dropFirst().first == "--list-live-states"
    static let isRenderingStates = isPresentingLiveState || isListingLiveStates || CommandLine.arguments.dropFirst().first == "--render-states"
    static let fixtureIdentifier = "co.chrisyork.upshot.render-states.\(UUID().uuidString)"
    static let fixtureRoot: URL? = isRenderingStates
        ? FileManager.default.temporaryDirectory.appendingPathComponent(fixtureIdentifier, isDirectory: true)
        : nil
    static let defaultsSuiteName = fixtureRoot?.appendingPathComponent("Preferences/\(fixtureIdentifier).plist").path ?? fixtureIdentifier

    static var defaults: UserDefaults {
        guard isRenderingStates else { return .standard }
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            fatalError("State renderer could not create its isolated defaults suite")
        }
        return defaults
    }

    static var applicationSupportDirectory: URL {
        if let fixtureRoot { return fixtureRoot.appendingPathComponent("Application Support/Upshot", isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Upshot", isDirectory: true)
    }

    static var configurationFileURL: URL {
        if let fixtureRoot { return fixtureRoot.appendingPathComponent("Configuration/config.toml") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/upshot/config.toml")
    }
}
