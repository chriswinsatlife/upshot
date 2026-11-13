import CryptoKit
import Darwin
import Foundation
import OSLog
import Synchronization

nonisolated enum AppLog {
    static let subsystem = "co.chrisyork.upshot"
    static let shared = AppLogStore()

    static func event(_ area: String, _ name: String, fields: [String: String] = [:]) {
        shared.record(area: area, event: name, fields: fields)
    }

    static func unifiedEvent(_ area: String, _ name: String, fields: [String: String] = [:]) {
        shared.record(area: area, event: name, fields: fields, persists: false)
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
        shared.prepareCrashCapture()
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
    struct Event: Sendable {
        let timestamp: Date
        let area: String
        let name: String
        let fields: [String: String]
        let persists: Bool
    }

    let fileURL: URL
    let sessionID = UUID().uuidString
    let processStart = Date()
    private let bufferLock = NSLock()
    private let crashWriter: CrashLogWriter
    private let writerQueue = DispatchQueue(label: "co.chrisyork.upshot.logging", qos: .utility)
    private let dropped = Atomic<UInt64>(0)
    private let unreportedDrops = Atomic<UInt64>(0)
    private let queueCapacity: Int
    private var pending: [Event] = []
    private var breadcrumbs = [Event?](repeating: nil, count: 200)
    private var breadcrumbPosition = 0
    private var drainScheduled = false
    private let maximumBytes: Int
    private let backupCount: Int
    private var descriptor: Int32 = -1
    private var lockDescriptor: Int32 = -1
    private var fileBytes = 0
    private var previousEvents: [String] = []
    private var loggers: [String: Logger] = [:]
    private let formatter: ISO8601DateFormatter

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Upshot", isDirectory: true), maximumBytes: Int = 5 * 1024 * 1024, backupCount: Int = 3, queueCapacity: Int = 1024) {
        fileURL = directory.appendingPathComponent("upshot.log")
        crashWriter = CrashLogWriter(directory: directory, sessionID: sessionID)
        self.maximumBytes = maximumBytes
        self.backupCount = backupCount
        self.queueCapacity = queueCapacity
        pending.reserveCapacity(queueCapacity)
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        writerQueue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let restored = Self.readPreviousEvents(fileURL: fileURL, backupCount: backupCount)
                bufferLock.lock()
                previousEvents = restored
                bufferLock.unlock()
                lockDescriptor = Darwin.open(directory.appendingPathComponent(".upshot-log.lock").path, O_WRONLY | O_CREAT | O_CLOEXEC, 0o600)
                openFile()
            } catch {
                reportFileFailure("file_log_unavailable", fields: ["error": AppLog.error(error)])
            }
        }
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
        if lockDescriptor >= 0 { Darwin.close(lockDescriptor) }
    }

    var droppedEventCount: UInt64 { dropped.load(ordering: .relaxed) }

    func record(area: String, event: String, fields: [String: String] = [:], persists: Bool = true) {
        guard bufferLock.try() else { countDrop(); return }
        guard pending.count < queueCapacity else {
            bufferLock.unlock()
            countDrop()
            return
        }
        let input = Event(timestamp: Date(), area: area, name: event, fields: fields, persists: persists)
        pending.append(input)
        breadcrumbs[breadcrumbPosition] = input
        breadcrumbPosition = (breadcrumbPosition + 1) % breadcrumbs.count
        let schedule = !drainScheduled
        drainScheduled = true
        bufferLock.unlock()
        if schedule { writerQueue.async { [self] in drain() } }
    }

    private func countDrop() {
        dropped.wrappingAdd(1, ordering: .relaxed)
        unreportedDrops.wrappingAdd(1, ordering: .relaxed)
    }

    private func drain() {
        while true {
            bufferLock.lock()
            let batch = pending
            pending = []
            pending.reserveCapacity(queueCapacity)
            if batch.isEmpty { drainScheduled = false }
            bufferLock.unlock()
            let lost = unreportedDrops.exchange(0, ordering: .relaxed)
            if lost > 0 {
                emit(Event(timestamp: Date(), area: "logging", name: "log_events_dropped", fields: ["count": String(lost), "total": String(droppedEventCount)], persists: true))
            }
            if batch.isEmpty { return }
            for event in batch { emit(event) }
        }
    }

    var crashFileURL: URL { crashWriter.fileURL }

    func prepareCrashCapture() {
        crashWriter.prepare()
    }

    @discardableResult
    func recordCrash(event: String, fields: [String: String], previousSession: Bool = false) -> Bool {
        crashWriter.write { deadline in
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var snapshot: [Event] = []
            var restored: [String] = []
            var status = "available"
            if bufferLock.try() {
                snapshot = (0..<breadcrumbs.count).compactMap { breadcrumbs[(breadcrumbPosition + $0) % breadcrumbs.count] }
                restored = previousEvents
                bufferLock.unlock()
            } else {
                status = "snapshot_busy"
            }
            var trail: [String] = []
            if previousSession {
                trail = restored
            } else {
                for input in snapshot {
                    guard DispatchTime.now().uptimeNanoseconds + 1_000_000 < deadline else { status = "deadline_exceeded"; break }
                    trail.append(format(input, using: dateFormatter))
                }
            }
            let crashID = UUID().uuidString
            var values = fields
            values["crash_id"] = crashID
            values["breadcrumb_count"] = String(trail.count)
            values["breadcrumb_status"] = status
            values["breadcrumb_source"] = previousSession ? "previous_logged_process" : "current_process"
            values["write_budget_ms"] = "25"
            var lines: [String] = []
            for (index, line) in trail.enumerated() {
                guard DispatchTime.now().uptimeNanoseconds + 500_000 < deadline else { values["breadcrumb_status"] = "deadline_exceeded"; break }
                lines.append(format(Event(timestamp: Date(), area: "crash", name: "crash_breadcrumb", fields: ["crash_id": crashID, "index": String(index), "original": line], persists: true), using: dateFormatter))
            }
            values["breadcrumb_count"] = String(lines.count)
            let crash = format(Event(timestamp: Date(), area: "crash", name: event, fields: values, persists: true), using: dateFormatter)
            return Data(([crash] + lines).joined(separator: "\n").appending("\n").utf8)
        }
    }

    @discardableResult
    func flush(timeout: TimeInterval = 5) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        writerQueue.async { [self] in
            drain()
            if descriptor >= 0 { _ = fsync(descriptor) }
            completion.signal()
        }
        return completion.wait(timeout: .now() + timeout) == .success
    }

    private func format(_ event: Event, using dateFormatter: ISO8601DateFormatter? = nil) -> String {
        var values = event.fields
        values["session_id"] = sessionID
        values["pid"] = String(getpid())
        values["process_start"] = String(processStart.timeIntervalSince1970)
        let encoded = values.keys.sorted().map { key in "\(token(key))=\(quote(AppLog.path(values[key] ?? "")))" }.joined(separator: " ")
        return "\((dateFormatter ?? formatter).string(from: event.timestamp)) area=\(token(event.area)) event=\(token(event.name)) \(encoded)"
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

    private func emit(_ event: Event) {
        let line = format(event)
        if event.fields["error"] != nil || event.fields["outcome"] == "failed" || event.name.contains("failed") {
            logger(area: event.area).error("\(line, privacy: .public)")
        } else {
            logger(area: event.area).notice("\(line, privacy: .public)")
        }
        if event.persists { append(Data((line + "\n").utf8)) }
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
        let line = format(Event(timestamp: Date(), area: "logging", name: event, fields: fields, persists: false))
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
