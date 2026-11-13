import Darwin
import Foundation
import MetricKit

@main
struct LoggingVerification {
    static func main() throws {
        AppLog.installExceptionHandler()
        let arguments = Array(CommandLine.arguments.dropFirst())
        let mode = arguments.first ?? "file"
        switch mode {
        case "file":
            AppLog.installExceptionHandler()
            let marker = arguments.count > 1 ? arguments[1] : UUID().uuidString
            AppLog.event("verification", "readable_probe", fields: ["marker": marker, "path": AppLog.shared.fileURL.path, "escaped": "line1\nline2=\"value\""])
            AppLog.shared.flush()
            let text = try String(contentsOf: AppLog.shared.fileURL, encoding: .utf8)
            precondition(text.contains("marker=\"\(marker)\""))
            precondition(text.contains("path=\"~/Library/Logs/Upshot/upshot.log\""))
            print("file_verification outcome=verified marker=\(marker)")
        case "queue":
            guard arguments.count == 2 else { throw VerificationFailure.argument }
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let store = AppLogStore(directory: directory, queueCapacity: 1024)
            precondition(store.flush())
            let descriptor = Darwin.open(directory.appendingPathComponent(".upshot-log.lock").path, O_WRONLY)
            precondition(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0)
            var costs: [UInt64] = []
            costs.reserveCapacity(20_000)
            var acceptedCosts: [UInt64] = []
            for index in 0..<20_000 {
                let droppedBefore = store.droppedEventCount
                let start = DispatchTime.now().uptimeNanoseconds
                store.record(area: "verification", event: "blocked_writer_probe", fields: ["index": String(index)])
                let cost = DispatchTime.now().uptimeNanoseconds - start
                costs.append(cost)
                if store.droppedEventCount == droppedBefore { acceptedCosts.append(cost) }
            }
            precondition(store.droppedEventCount > 0)
            _ = flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
            precondition(store.flush())
            let text = try String(contentsOf: store.fileURL, encoding: .utf8)
            precondition(text.contains("event=log_events_dropped "))
            let before = text
            store.record(area: "verification", event: "unified_only_probe", fields: ["marker": "queue_review_unified_only"], persists: false)
            precondition(store.flush())
            let after = try String(contentsOf: store.fileURL, encoding: .utf8)
            precondition(after == before)
            costs.sort()
            acceptedCosts.sort()
            precondition(!acceptedCosts.isEmpty)
            print("queue_verification outcome=verified events=20000 process_lock=held dropped=\(store.droppedEventCount) mean_ns=\(costs.reduce(0, +) / UInt64(costs.count)) p50_ns=\(costs[10000]) p95_ns=\(costs[19000]) p99_ns=\(costs[19800]) maximum_ns=\(costs.last ?? 0) accepted=\(acceptedCosts.count) accepted_mean_ns=\(acceptedCosts.reduce(0, +) / UInt64(acceptedCosts.count)) accepted_p50_ns=\(acceptedCosts[acceptedCosts.count / 2]) accepted_p99_ns=\(acceptedCosts[acceptedCosts.count * 99 / 100]) unified_only_file=absent")
        case "blocked-crash":
            guard arguments.count == 2 else { throw VerificationFailure.argument }
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let store = AppLogStore(directory: directory)
            store.prepareCrashCapture()
            precondition(store.flush())
            for index in 0..<225 {
                store.record(area: "verification", event: "breadcrumb_probe", fields: ["index": String(index)])
                precondition(store.flush())
            }
            let descriptor = Darwin.open(directory.appendingPathComponent(".upshot-log.lock").path, O_WRONLY)
            precondition(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0)
            store.record(area: "verification", event: "writer_lock_probe")
            let started = DispatchTime.now().uptimeNanoseconds
            let written = store.recordCrash(event: "blocked_writer_crash", fields: ["reason": "verification"])
            let elapsed = DispatchTime.now().uptimeNanoseconds - started
            precondition(written)
            let text = try String(contentsOf: store.crashFileURL, encoding: .utf8)
            precondition(text.contains("event=blocked_writer_crash "))
            precondition(text.contains("breadcrumb_count=\"200\""))
            precondition(elapsed < 100_000_000)
            _ = flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
            precondition(store.flush())
            print("blocked_crash_verification outcome=verified process_lock=held breadcrumbs=200 elapsed_ns=\(elapsed) independent_file=present")
        case "archive":
            guard arguments.count == 3 else { throw VerificationFailure.argument }
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let store = AppLogStore(directory: directory)
            for index in 0..<2 {
                store.record(area: "verification", event: "process_archive_probe", fields: ["index": String(index), "marker": arguments[2]])
                precondition(store.flush())
            }
            print("archive_verification outcome=written pid=\(getpid()) process_start=\(store.processStart.timeIntervalSince1970) marker=\(arguments[2])")
        case "correlation":
            guard arguments.count == 2 else { throw VerificationFailure.argument }
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let store = AppLogStore(directory: directory)
            store.prepareCrashCapture()
            precondition(store.flush())
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let urls = try FileManager.default.contentsOfDirectory(at: store.breadcrumbStore.directory, includingPropertiesForKeys: nil)
            let snapshots = try urls.filter { $0.pathExtension == "json" }.map { try decoder.decode(ProcessBreadcrumbSnapshot.self, from: Data(contentsOf: $0)) }.sorted { $0.processStart < $1.processStart }
            precondition(snapshots.count == 2)
            let first = snapshots[0]
            let second = snapshots[1]
            precondition(first.processIdentifier != second.processIdentifier)
            guard let firstEnd = first.events.last?.timestamp, let secondEnd = second.events.last?.timestamp else { throw VerificationFailure.argument }
            precondition(firstEnd < second.processStart)
            let service = CrashDiagnostics(stateDirectory: directory, logStore: store)
            func verify(_ name: String, status: String, count: Int, processIdentifier: Int32? = nil, processStart: Date? = nil, range: ClosedRange<Date>? = nil) throws {
                precondition(service.recordDiagnostic("metrickit_crash", fields: ["case": name], processIdentifier: processIdentifier, processStart: processStart, range: range))
                let lines = try String(contentsOf: store.crashFileURL, encoding: .utf8).split(separator: "\n").map(String.init)
                guard let header = lines.last(where: { $0.contains("event=metrickit_crash ") && $0.contains("case=\"\(name)\"") }) else { throw VerificationFailure.argument }
                precondition(header.contains("breadcrumb_status=\"\(status)\""))
                precondition(header.contains("breadcrumb_count=\"\(count)\""))
                if count > 0 {
                    precondition(header.contains("breadcrumb_pid=\"\(first.processIdentifier)\""))
                    let trail = lines.suffix(count).joined(separator: "\n")
                    precondition(trail.contains(#"marker=\"first\""#))
                    precondition(!trail.contains(#"marker=\"second\""#))
                }
            }
            try verify("historical_pid", status: "matched_process_identifier", count: 2, processIdentifier: first.processIdentifier)
            try verify("historical_range", status: "matched_time_range", count: 2, range: first.processStart...firstEnd)
            try verify("unrelated_range", status: "no_match", count: 0, range: first.processStart.addingTimeInterval(-10000)...first.processStart.addingTimeInterval(-9999))
            try verify("ambiguous_range", status: "ambiguous_match", count: 0, range: first.processStart...secondEnd)
            try verify("unknown_pid", status: "no_match", count: 0, processIdentifier: Int32.max)
            try verify("missing_identity", status: "no_identity", count: 0)
            let earlier = first.processStart.addingTimeInterval(-3600)
            try store.breadcrumbStore.save(ProcessBreadcrumbSnapshot(processIdentifier: first.processIdentifier, processStart: earlier, sessionIdentifier: "pid-reuse-verification", events: [ProcessBreadcrumb(timestamp: earlier.addingTimeInterval(1), line: "earlier_process_verification")]))
            try verify("reused_pid", status: "ambiguous_match", count: 0, processIdentifier: first.processIdentifier)
            try verify("reused_pid_start", status: "matched_process_identifier", count: 2, processIdentifier: first.processIdentifier, processStart: first.processStart)
            try verify("wrong_process_start", status: "no_match", count: 0, processIdentifier: first.processIdentifier, processStart: first.processStart.addingTimeInterval(-2000))
            print("correlation_verification outcome=verified cases=9 historical_pid=matched historical_range=matched unrelated=empty ambiguous=empty missing_identity=empty pid_reuse=disambiguated latest_process=excluded")
        case "exception":
            AppLog.installExceptionHandler()
            for index in 0..<225 {
                AppLog.event("verification", "breadcrumb_probe", fields: ["index": String(index)])
                precondition(AppLog.shared.flush())
            }
            NSException(name: .invalidArgumentException, reason: "Upshot logging verification exception", userInfo: nil).raise()
        case "rotation":
            guard arguments.count == 2 else { throw VerificationFailure.argument }
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let store = AppLogStore(directory: directory, maximumBytes: 1500, backupCount: 3)
            DispatchQueue.concurrentPerform(iterations: 100) { index in
                store.record(area: "verification", event: "rotation_probe", fields: ["index": String(index), "payload": String(repeating: "a", count: 64)])
            }
            precondition(store.flush())
            for index in 0..<100 {
                store.record(area: "verification", event: "rotation_probe", fields: ["index": String(index), "payload": String(repeating: "a", count: 64)])
                precondition(store.flush())
            }
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("upshot.log") }
            precondition(urls.count == 4)
            var count = 0
            for url in urls {
                let data = try Data(contentsOf: url)
                precondition(data.count <= 1500)
                let text = String(decoding: data, as: UTF8.self)
                precondition(text.hasSuffix("\n"))
                for line in text.split(separator: "\n") {
                    precondition(line.contains("area=verification event=rotation_probe"))
                    precondition(line.components(separatedBy: "event=").count == 2)
                    count += 1
                }
            }
            print("rotation_verification outcome=verified files=4 maximum_bytes=1500 readable_lines=\(count) concurrent_writers=100")
        case "scan":
            guard arguments.count == 2 else { throw VerificationFailure.argument }
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let reports = directory.appendingPathComponent("reports", isDirectory: true)
            let state = directory.appendingPathComponent("state", isDirectory: true)
            try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
            let header: [String: Any] = ["bundleID": AppLog.subsystem, "incident_id": "logging-verification-incident"]
            let body: [String: Any] = ["bundleInfo": ["CFBundleIdentifier": AppLog.subsystem], "exception": ["type": "EXC_CRASH", "signal": "SIGABRT"], "termination": ["namespace": "SIGNAL", "code": 6]]
            let text = String(decoding: try JSONSerialization.data(withJSONObject: header), as: UTF8.self) + "\n" + String(decoding: try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]), as: UTF8.self)
            try text.write(to: reports.appendingPathComponent("Upshot-verification.ips"), atomically: true, encoding: .utf8)
            let legacy = "Identifier: co.chrisyork.upshot.dev\nException Type: EXC_CRASH (SIGABRT)\nIncident Identifier: logging-verification-legacy\n"
            try legacy.write(to: reports.appendingPathComponent("Upshot Dev-verification.crash"), atomically: true, encoding: .utf8)
            precondition(CrashDiagnostics.crashReportFields(text.replacingOccurrences(of: AppLog.subsystem, with: "com.other.application"), filename: "Upshot-other.ips") == nil)
            precondition(CrashDiagnostics.crashReportFields("invalid", filename: "Upshot-invalid.ips") == nil)
            let service = CrashDiagnostics(stateDirectory: state)
            let before = (try? String(contentsOf: AppLog.shared.crashFileURL, encoding: .utf8))?.components(separatedBy: "event=system_crash_report ").count ?? 1
            let now = Date().addingTimeInterval(1)
            service.importCrashReports(from: reports, stateDirectory: state, now: now)
            service.importCrashReports(from: reports, stateDirectory: state, now: now.addingTimeInterval(1))
            precondition(AppLog.shared.flush())
            let after = try String(contentsOf: AppLog.shared.crashFileURL, encoding: .utf8).components(separatedBy: "event=system_crash_report ").count
            precondition(after - before == 2)
            print("scan_verification outcome=verified ips=1 legacy=1 unrelated=rejected malformed=rejected second_scan=0")
        case "metrickit":
            guard arguments.count == 2 else { throw VerificationFailure.argument }
            let state = URL(fileURLWithPath: arguments[1], isDirectory: true)
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            let service = CrashDiagnostics(stateDirectory: state)
            MXMetricManager.shared.add(service)
            let payloads = MXMetricManager.shared.pastDiagnosticPayloads
            service.didReceive(payloads)
            MXMetricManager.shared.remove(service)
            print("metrickit_verification outcome=subscription_completed past_payloads=\(payloads.count)")
        default:
            throw VerificationFailure.argument
        }
    }

    enum VerificationFailure: Error {
        case argument
    }
}
