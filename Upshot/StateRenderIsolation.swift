import Foundation

struct StateRenderIsolation {
    struct Entry: Codable, Equatable {
        let path: String
        let modificationTime: Double?
        let size: UInt64?
    }

    let roots: [URL]
    let before: [Entry]

    init() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots = [home.appendingPathComponent("Library/Application Support/Upshot", isDirectory: true),
                 home.appendingPathComponent(".config/upshot", isDirectory: true),
                 home.appendingPathComponent("Library/Preferences/co.chrisyork.upshot.plist"),
                 home.appendingPathComponent("Library/Preferences/co.chrisyork.upshot.dev.plist")]
        before = try Self.snapshot(roots)
    }

    func validateOutput(_ output: URL) throws {
        let resolved = output.resolvingSymlinksInPath().path
        guard !roots.contains(where: { resolved == $0.path || resolved.hasPrefix($0.path + "/") }) else {
            throw StateRenderFailure(message: "The output directory overlaps protected user storage")
        }
    }

    func writeSnapshot(to url: URL) throws {
        try Self.write(before, to: url)
    }

    func verify(to output: URL) throws {
        let after = try Self.snapshot(roots)
        try Self.write(after, to: output.appendingPathComponent("isolation-after.json"))
        guard before == after else { throw StateRenderFailure(message: "Protected file modification times changed during rendering") }
        AppLog.event("rendering", "state_renderer_isolation", fields: ["defaultsSuite": String(describing: UpshotStorage.fixtureIdentifier), "outcome": "verified", "protectedEntries": String(describing: before.count)])
    }

    private static func write(_ entries: [Entry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: url, options: .atomic)
    }

    private static func snapshot(_ roots: [URL]) throws -> [Entry] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser.path
        var entries: [Entry] = []
        func append(_ url: URL) throws {
            let path = url.path.replacingOccurrences(of: home + "/", with: "~/")
            guard manager.fileExists(atPath: url.path) else { entries.append(Entry(path: path, modificationTime: nil, size: nil)); return }
            let attributes = try manager.attributesOfItem(atPath: url.path)
            entries.append(Entry(path: path, modificationTime: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
                                 size: (attributes[.type] as? FileAttributeType) == .typeRegular ? attributes[.size] as? UInt64 : nil))
        }
        for root in roots {
            try append(root)
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue {
                guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil) else { throw StateRenderFailure(message: "Could not inspect protected file modification times") }
                for case let url as URL in enumerator { try append(url) }
            }
        }
        return entries.sorted { $0.path < $1.path }
    }
}
