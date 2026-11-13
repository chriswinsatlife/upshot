import Foundation
import MetricKit

@main
struct LoggingVerification {
    static func main() throws {
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
        case "exception":
            AppLog.installExceptionHandler()
            for index in 0..<225 { AppLog.event("verification", "breadcrumb_probe", fields: ["index": String(index)]) }
            NSException(name: .invalidArgumentException, reason: "Upshot logging verification exception", userInfo: nil).raise()
        case "rotation":
            guard arguments.count == 2 else { throw VerificationFailure.argument }
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            let store = AppLogStore(directory: directory, maximumBytes: 1500, backupCount: 3)
            DispatchQueue.concurrentPerform(iterations: 100) { index in
                store.record(area: "verification", event: "rotation_probe", fields: ["index": String(index), "payload": String(repeating: "a", count: 64)])
            }
            store.flush()
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
            let before = try String(contentsOf: AppLog.shared.fileURL, encoding: .utf8).components(separatedBy: "event=system_crash_report ").count
            let now = Date().addingTimeInterval(1)
            service.importCrashReports(from: reports, stateDirectory: state, now: now)
            service.importCrashReports(from: reports, stateDirectory: state, now: now.addingTimeInterval(1))
            let after = try String(contentsOf: AppLog.shared.fileURL, encoding: .utf8).components(separatedBy: "event=system_crash_report ").count
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
