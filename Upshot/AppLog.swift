import CryptoKit
import Darwin
import Foundation
import OSLog

nonisolated enum AppLog {
    static let subsystem = "co.chrisyork.upshot"
    static let shared = AppLogStore()

    static func event(_ area: String, _ name: String, fields: [String: String] = [:]) {
        shared.record(area: area, event: name, fields: fields)
    }

    static func error(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain):\(error.code)"
    }

    static func identifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func path(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        return path.replacingOccurrences(of: home + "/", with: "~/")
    }

    static func installExceptionHandler() {
        _ = shared
        NSSetUncaughtExceptionHandler { exception in
            AppLog.shared.recordCrash(event: "uncaught_exception", fields: [
                "name": exception.name.rawValue,
                "reason": AppLog.exceptionReason(exception.reason),
                "call_stack": exception.callStackSymbols.joined(separator: " | ")
            ])
        }
    }

    static func exceptionReason(_ reason: String?) -> String {
        guard let reason else { return "unavailable" }
        if reason.range(of: #"^\*\*\* -\[[A-Za-z_][A-Za-z0-9_]* initWithObjects:forKeys:count:\]: attempt to insert nil object from objects\[[0-9]+\]$"#, options: .regularExpression) != nil {
            return reason
        }
        if reason.contains("index"), reason.contains("beyond bounds") {
            return "Collection index beyond bounds"
        }
        if reason == "Upshot logging verification exception" { return reason }
        return "redacted_exception_reason"
    }
}

nonisolated final class AppLogStore: @unchecked Sendable {
    let fileURL: URL
    let sessionID = UUID().uuidString
    let previousEvents: [String]
    private let lock = NSRecursiveLock()
    private let maximumBytes: Int
    private let backupCount: Int
    private var descriptor: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var fileBytes = 0
    private var events: [String] = []
    private var loggers: [String: Logger] = [:]
    private let formatter: ISO8601DateFormatter
    private var recordingCrash = false

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Upshot", isDirectory: true), maximumBytes: Int = 5 * 1024 * 1024, backupCount: Int = 3) {
        fileURL = directory.appendingPathComponent("upshot.log")
        self.maximumBytes = maximumBytes
        self.backupCount = backupCount
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        previousEvents = Self.readPreviousEvents(fileURL: fileURL, backupCount: backupCount)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            lockDescriptor = Darwin.open(directory.appendingPathComponent(".upshot-log.lock").path, O_WRONLY | O_CREAT | O_CLOEXEC, 0o600)
            openFile()
        } catch {
            reportFileFailure("file_log_unavailable", fields: ["error": AppLog.error(error)])
        }
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
    }

    func record(area: String, event: String, fields: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        let line = format(area: area, event: event, fields: fields)
        events.append(line)
        if events.count > 200 { events.removeFirst(events.count - 200) }
        emit(line, area: area, isFailure: fields["error"] != nil || fields["outcome"] == "failed" || event.contains("failed"))
    }

    func recordCrash(event: String, fields: [String: String], previousSession: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        guard !recordingCrash else { return }
        recordingCrash = true
        defer { recordingCrash = false }
        let breadcrumbs: [String]
        if previousSession, let processID = fields["crashed_pid"] {
            breadcrumbs = previousEvents.filter { $0.contains("pid=\"\(processID)\"") }
        } else {
            breadcrumbs = previousSession ? previousEvents : events
        }
        let crashID = UUID().uuidString
        var crashFields = fields
        crashFields["crash_id"] = crashID
        crashFields["breadcrumb_count"] = String(breadcrumbs.count)
        crashFields["breadcrumb_source"] = previousSession ? "previous_logged_process" : "current_process"
        let crash = format(area: "crash", event: event, fields: crashFields)
        let trail = breadcrumbs.enumerated().map { index, line in
            format(area: "crash", event: "crash_breadcrumb", fields: ["crash_id": crashID, "index": String(index), "original": line])
        }
        let lines = [crash] + trail
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        append(data, synchronize: true)
        logger(area: "crash").fault("\(crash, privacy: .public)")
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        if descriptor >= 0 { _ = fsync(descriptor) }
    }

    private func format(area: String, event: String, fields: [String: String]) -> String {
        var values = fields
        values["session_id"] = sessionID
        values["pid"] = String(getpid())
        let encoded = values.keys.sorted().map { key in "\(token(key))=\(quote(AppLog.path(values[key] ?? "")))" }.joined(separator: " ")
        return "\(formatter.string(from: Date())) area=\(token(area)) event=\(token(event)) \(encoded)"
    }

    private func token(_ value: String) -> String {
        String(value.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? Character($0) : "_" })
    }

    private func quote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\0", with: "\\0")
        return "\"\(escaped)\""
    }

    private func logger(area: String) -> Logger {
        if let logger = loggers[area] { return logger }
        let logger = Logger(subsystem: AppLog.subsystem, category: area)
        loggers[area] = logger
        return logger
    }

    private func emit(_ line: String, area: String, isFailure: Bool) {
        if isFailure {
            logger(area: area).error("\(line, privacy: .public)")
        } else {
            logger(area: area).notice("\(line, privacy: .public)")
        }
        let data = Data((line + "\n").utf8)
        append(data)
    }

    private func append(_ data: Data, synchronize: Bool = false) {
        if lockDescriptor >= 0 {
            while flock(lockDescriptor, LOCK_EX) != 0 {
                if errno != EINTR { return }
            }
        }
        defer { if lockDescriptor >= 0 { _ = flock(lockDescriptor, LOCK_UN) } }
        var openedStatus = stat()
        var currentStatus = stat()
        if descriptor < 0 || fstat(descriptor, &openedStatus) != 0 || stat(fileURL.path, &currentStatus) != 0 || openedStatus.st_ino != currentStatus.st_ino {
            if descriptor >= 0 { Darwin.close(descriptor) }
            openFile()
        } else {
            fileBytes = Int(currentStatus.st_size)
        }
        rotateIfNeeded(adding: data.count)
        writeFile(data)
        if synchronize, descriptor >= 0 { _ = fsync(descriptor) }
    }

    private func openFile() {
        descriptor = Darwin.open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o600)
        if descriptor >= 0 {
            var status = stat()
            if fstat(descriptor, &status) == 0 { fileBytes = Int(status.st_size) }
        } else {
            reportFileFailure("file_log_open_failed", fields: ["errno": String(errno)])
        }
    }

    private func rotateIfNeeded(adding bytes: Int) {
        guard fileBytes > 0, fileBytes + bytes > maximumBytes else { return }
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
        if backupCount > 0 {
            for index in stride(from: backupCount, through: 1, by: -1) {
                let source = index == 1 ? fileURL.path : fileURL.path + ".\(index - 1)"
                let destination = fileURL.path + ".\(index)"
                _ = Darwin.rename(source, destination)
            }
        } else {
            _ = Darwin.unlink(fileURL.path)
        }
        fileBytes = 0
        openFile()
    }

    private func writeFile(_ data: Data) {
        guard descriptor >= 0 else { return }
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let result = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else {
                    reportFileFailure("file_log_write_failed", fields: ["errno": String(errno)])
                    return
                }
                offset += result
                fileBytes += result
            }
        }
    }

    private func reportFileFailure(_ event: String, fields: [String: String]) {
        let line = format(area: "logging", event: event, fields: fields)
        logger(area: "logging").error("\(line, privacy: .public)")
    }

    private static func readPreviousEvents(fileURL: URL, backupCount: Int) -> [String] {
        var lines: [String] = []
        for index in stride(from: backupCount, through: 0, by: -1) {
            let url = index == 0 ? fileURL : URL(fileURLWithPath: fileURL.path + ".\(index)")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            lines.append(contentsOf: text.split(separator: "\n").map(String.init).filter { !$0.contains("area=crash ") })
        }
        guard let last = lines.last,
              let range = last.range(of: "session_id=\""),
              let end = last[range.upperBound...].firstIndex(of: "\"") else { return [] }
        let session = String(last[range.upperBound..<end])
        return Array(lines.filter { $0.contains("session_id=\"\(session)\"") }.suffix(200))
    }
}
