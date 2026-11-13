import Darwin
import Foundation

nonisolated struct ProcessBreadcrumb: Codable, Sendable {
    let timestamp: Date
    let line: String
}

nonisolated struct ProcessBreadcrumbSnapshot: Codable, Sendable {
    let processIdentifier: Int32
    let processStart: Date
    let sessionIdentifier: String
    let events: [ProcessBreadcrumb]
}

nonisolated struct ProcessBreadcrumbSelection: Sendable {
    let status: String
    let snapshot: ProcessBreadcrumbSnapshot?
    let events: [ProcessBreadcrumb]
}

nonisolated struct ProcessBreadcrumbStore: Sendable {
    let directory: URL

    static let currentProcessStart: Date? = {
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &information, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(information.pbi_start_tvsec) + Double(information.pbi_start_tvusec) / 1_000_000)
    }()

    func save(_ snapshot: ProcessBreadcrumbSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let filename = "\(snapshot.processIdentifier)-\(snapshot.sessionIdentifier).json"
        let url = directory.appendingPathComponent(filename)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func select(processIdentifier: Int32? = nil, processStart: Date? = nil, range: ClosedRange<Date>? = nil) -> ProcessBreadcrumbSelection {
        guard processIdentifier != nil || range != nil else {
            return ProcessBreadcrumbSelection(status: "no_identity", snapshot: nil, events: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let snapshots = urls.filter { $0.pathExtension == "json" }.compactMap { url -> ProcessBreadcrumbSnapshot? in
            guard let data = try? Data(contentsOf: url), let value = try? decoder.decode(ProcessBreadcrumbSnapshot.self, from: data), !value.events.isEmpty else { return nil }
            return value
        }
        let candidates = snapshots.filter { snapshot in
            if let processIdentifier, snapshot.processIdentifier != processIdentifier { return false }
            if let processStart, abs(snapshot.processStart.timeIntervalSince(processStart)) >= 0.001 { return false }
            if let range {
                guard snapshot.processStart <= range.upperBound,
                      snapshot.events.contains(where: { range.contains($0.timestamp) }) else { return false }
            }
            return true
        }
        guard candidates.count == 1, let snapshot = candidates.first else {
            return ProcessBreadcrumbSelection(status: candidates.isEmpty ? "no_match" : "ambiguous_match", snapshot: nil, events: [])
        }
        let events = snapshot.events.filter { event in
            guard let range else { return true }
            return event.timestamp <= range.upperBound
        }
        let status = processIdentifier != nil ? "matched_process_identifier" : "matched_time_range"
        return ProcessBreadcrumbSelection(status: status, snapshot: snapshot, events: Array(events.suffix(200)))
    }
}
