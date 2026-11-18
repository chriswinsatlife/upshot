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

    static func trashItem(at url: URL) throws -> URL? {
        guard let fixtureRoot else {
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            return destination as URL?
        }
        let trash = fixtureRoot.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var destination = trash.appendingPathComponent(url.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = trash.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(suffix)").appendingPathExtension(url.pathExtension)
            suffix += 1
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    static var configurationFileURL: URL {
        if let fixtureRoot { return fixtureRoot.appendingPathComponent("Configuration/config.toml") }
        let fileName = DevelopmentCaptureMarker.isDevelopmentBuild ? "config.dev.toml" : "config.toml"
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/upshot/\(fileName)")
    }
}
