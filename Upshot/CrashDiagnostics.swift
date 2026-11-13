import CryptoKit
import Foundation
import MetricKit

nonisolated final class CrashDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = CrashDiagnostics()
    private let lock = NSLock()
    private var importedDiagnostics: Set<String> = []
    private let stateDirectory: URL

    init(stateDirectory: URL = AppLog.shared.fileURL.deletingLastPathComponent()) {
        self.stateDirectory = stateDirectory
        super.init()
    }

    func start() {
        AppLog.installExceptionHandler()
        AppLog.event("application", "process_started", fields: [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unavailable",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unavailable",
            "operating_system": ProcessInfo.processInfo.operatingSystemVersionString
        ])
        let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        importCrashReports(from: reports, stateDirectory: stateDirectory)
        MXMetricManager.shared.add(self)
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
        AppLog.event("crash", "metrickit_subscribed")
    }

    func importCrashReports(from directory: URL, stateDirectory: URL, now: Date = Date()) {
        let stateURL = stateDirectory.appendingPathComponent("crash-report-checkpoint.json")
        let previous = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(Date.self, from: $0) } ?? .distantPast
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
            var count = 0
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard (url.lastPathComponent.hasPrefix("Upshot-") || url.lastPathComponent.hasPrefix("Upshot Dev-")), ["ips", "crash"].contains(url.pathExtension) else { continue }
                let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard attributes.isRegularFile == true, let modified = attributes.contentModificationDate,
                      modified > previous, modified <= now else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                guard let fields = Self.crashReportFields(text, filename: url.lastPathComponent) else { continue }
                AppLog.shared.recordCrash(event: "system_crash_report", fields: fields, previousSession: true)
                count += 1
            }
            AppLog.event("crash", "system_crash_scan_completed", fields: ["reports": String(count)])
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(now).write(to: stateURL, options: .atomic)
        } catch {
            AppLog.event("crash", "system_crash_scan_failed", fields: ["error": AppLog.error(error)])
        }
    }

    static func crashReportFields(_ text: String, filename: String) -> [String: String]? {
        if filename.hasSuffix(".crash") {
            let lines = text.split(separator: "\n").map(String.init)
            func value(_ key: String) -> String? {
                lines.first(where: { $0.hasPrefix(key + ":") }).map { String($0.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces) }
            }
            guard value("Identifier") == AppLog.subsystem || value("Identifier") == AppLog.subsystem + ".dev" else { return nil }
            return ["report": filename, "exception": value("Exception Type") ?? "unavailable", "incident_id": value("Incident Identifier") ?? "unavailable", "crash_time": value("Date/Time") ?? "unavailable"]
        }
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first,
              let header = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] else { return nil }
        let body: [String: Any]
        if parts.count == 2, let decoded = try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any] {
            body = decoded
        } else {
            body = header
        }
        let bundle = body["bundleInfo"] as? [String: Any]
        let identifier = bundle?["CFBundleIdentifier"] as? String ?? header["bundleID"] as? String
        guard identifier == AppLog.subsystem || identifier == AppLog.subsystem + ".dev" else { return nil }
        let exception = body["exception"] as? [String: Any]
        let termination = body["termination"] as? [String: Any]
        var fields = ["report": filename, "incident_id": body["incident"] as? String ?? header["incident_id"] as? String ?? "unavailable", "exception": exception?["type"] as? String ?? "unavailable", "signal": exception?["signal"] as? String ?? "unavailable", "termination_namespace": termination?["namespace"] as? String ?? "unavailable", "crash_time": body["captureTime"] as? String ?? header["timestamp"] as? String ?? "unavailable"]
        if let code = termination?["code"] as? NSNumber { fields["termination_code"] = code.stringValue }
        return fields
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        lock.lock()
        defer { lock.unlock() }
        let checkpointURL = stateDirectory.appendingPathComponent("metrickit-checkpoint.json")
        if let data = try? Data(contentsOf: checkpointURL), let values = try? JSONDecoder().decode(Set<String>.self, from: data) {
            importedDiagnostics.formUnion(values)
        }
        for payload in payloads {
            for diagnostic in payload.crashDiagnostics ?? [] {
                let stack = diagnostic.callStackTree.jsonRepresentation()
                let fingerprint = SHA256.hash(data: diagnostic.jsonRepresentation()).map { String(format: "%02x", $0) }.joined()
                guard !importedDiagnostics.contains(fingerprint) else { continue }
                var fields = ["diagnostic_id": fingerprint, "signal": diagnostic.signal?.stringValue ?? "unavailable", "exception_type": diagnostic.exceptionType?.stringValue ?? "unavailable", "exception_code": diagnostic.exceptionCode?.stringValue ?? "unavailable", "period_start": String(payload.timeStampBegin.timeIntervalSince1970), "period_end": String(payload.timeStampEnd.timeIntervalSince1970)]
                if let reason = diagnostic.exceptionReason {
                    fields["exception_name"] = reason.exceptionName
                    fields["reason"] = AppLog.exceptionReason(reason.composedMessage)
                }
                if let object = try? JSONSerialization.jsonObject(with: stack),
                   let compact = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                   let text = String(data: compact, encoding: .utf8) {
                    fields["call_stack"] = text
                }
                AppLog.shared.recordCrash(event: "metrickit_crash", fields: fields, previousSession: true)
                importedDiagnostics.insert(fingerprint)
            }
        }
        do {
            try JSONEncoder().encode(importedDiagnostics).write(to: checkpointURL, options: .atomic)
        } catch {
            AppLog.event("crash", "metrickit_checkpoint_failed", fields: ["error": AppLog.error(error)])
        }
    }
}
