import Darwin
import Foundation
import Synchronization

nonisolated final class CrashLogWriter: @unchecked Sendable {
    let fileURL: URL
    private let preparationLock = NSLock()
    private let captureLock = NSLock()
    private let prepared = Atomic<Bool>(false)
    private var descriptor: Int32 = -1

    init(directory: URL, sessionID: String) {
        fileURL = directory.appendingPathComponent("upshot-crash-\(getpid())-\(sessionID).log")
    }

    func prepare() {
        preparationLock.lock()
        defer { preparationLock.unlock() }
        guard !prepared.load(ordering: .acquiring) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            descriptor = Darwin.open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NONBLOCK, 0o600)
            if descriptor >= 0 { prepared.store(true, ordering: .releasing) }
        } catch {
        }
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
        if (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) == 0 {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    @discardableResult
    func write(_ encode: (UInt64) -> Data) -> Bool {
        guard prepared.load(ordering: .acquiring), captureLock.try() else { return false }
        defer { captureLock.unlock() }
        let deadline = DispatchTime.now().uptimeNanoseconds + 25_000_000
        let data = encode(deadline)
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                if offset > 0, DispatchTime.now().uptimeNanoseconds >= deadline { return false }
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR {
                    if DispatchTime.now().uptimeNanoseconds >= deadline { return false }
                    continue
                }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }
}
