import CryptoKit
import Darwin
import Foundation

enum LiveStatePrivateBundle {
    static let sourceEnvironmentKey = "UYUNI_LIVE_STATE_PRIVATE_BUNDLE_SOURCE"
    static let rootDirectoryName = "UyuniLiveState"
    static let completeMarkerName = "complete"
    static let lockFileName = "in_use.lock"
    static let stagingPrefix = ".staging-"
    static let stagingLifetimeSeconds: TimeInterval = 3600
    static let preparationAttempts = 3

    struct Copy {
        let bundle: URL
        let directory: URL
        let key: String
        let created: Bool
        let removedDirectories: [String]
        let lockDescriptor: Int32
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static var defaultRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    static func enter(bundle: URL = Bundle.main.bundleURL, executable: URL? = Bundle.main.executableURL, root: URL = defaultRoot) {
        if let source = ProcessInfo.processInfo.environment[sourceEnvironmentKey] {
            unsetenv(sourceEnvironmentKey)
            let rootPath = root.resolvingSymlinksInPath().path + "/"
            guard bundle.resolvingSymlinksInPath().path.hasPrefix(rootPath) else {
                fail("The environment names \(source) as the bundle this process was copied from, but the process runs from \(bundle.path), which is outside \(root.path).")
            }
            LiveStateLog.event("private_bundle_entered", ["sourceBundle": source, "bundle": bundle.path])
            return
        }
        guard bundle.pathExtension == "app", let executable else {
            LiveStateLog.event("private_bundle_skipped", ["bundle": bundle.path, "reason": "The main bundle is not an application bundle, so LaunchServices does not open it as an application."])
            return
        }
        let started = ContinuousClock.now
        do {
            let bundlePath = bundle.resolvingSymlinksInPath().path
            let executablePath = executable.resolvingSymlinksInPath().path
            guard executablePath.hasPrefix(bundlePath + "/") else {
                throw Failure(description: "The executable \(executablePath) is outside the bundle \(bundlePath).")
            }
            let copy = try prepareCopy(of: bundle, in: root)
            let target = copy.bundle.path + executablePath.dropFirst(bundlePath.count)
            LiveStateLog.event("private_bundle_prepared", [
                "sourceBundle": bundle.path, "bundle": copy.bundle.path, "executable": target, "key": copy.key,
                "created": copy.created, "removedDirectories": copy.removedDirectories,
                "milliseconds": LiveStateLog.milliseconds(since: started),
            ])
            setenv(sourceEnvironmentKey, bundle.path, 1)
            var arguments = CommandLine.arguments
            arguments[0] = target
            let pointers = arguments.map { strdup($0) } + [nil]
            execv(target, pointers)
            let code = errno
            throw Failure(description: "The executable \(target) could not be started: \(String(cString: strerror(code))).")
        } catch {
            fail("The application could not be started from a private copy of \(bundle.path): \(error)")
        }
    }

    static func fail(_ reason: String) -> Never {
        LiveStateOutput.write(["event": "live_state_failed", "reason": reason])
        LiveStateLog.event("live_state_run_finished", ["exitStatus": 1, "reason": reason])
        exit(1)
    }

    static func contentKey(of bundle: URL) throws -> String {
        let base = bundle.path
        guard let enumerator = FileManager.default.enumerator(atPath: base) else {
            throw Failure(description: "The bundle \(base) could not be listed.")
        }
        var lines: [String] = []
        while let relative = enumerator.nextObject() as? String {
            let path = base + "/" + relative
            var status = stat()
            guard lstat(path, &status) == 0 else {
                let code = errno
                throw Failure(description: "The file \(path) could not be read: \(String(cString: strerror(code))).")
            }
            switch status.st_mode & S_IFMT {
            case S_IFREG:
                lines.append("file \(relative) \(status.st_size) \(status.st_mtimespec.tv_sec).\(status.st_mtimespec.tv_nsec)")
            case S_IFLNK:
                lines.append("link \(relative) \(try FileManager.default.destinationOfSymbolicLink(atPath: path))")
            default:
                continue
            }
        }
        lines.sort()
        let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func prepareCopy(of source: URL, in root: URL) throws -> Copy {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let key = try contentKey(of: source)
        let directory = root.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(key)", isDirectory: true)
        let bundle = directory.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        let marker = directory.appendingPathComponent(completeMarkerName).path
        var created = false
        var problems: [String] = []
        for _ in 0..<preparationAttempts {
            if !fileManager.fileExists(atPath: marker) {
                if fileManager.fileExists(atPath: directory.path), !removeDirectoryIfUnused(directory) {
                    problems.append("the incomplete copy \(directory.path) is in use")
                    continue
                }
                if try createCopy(of: source, at: directory, in: root) { created = true }
            }
            let descriptor = open(directory.appendingPathComponent(lockFileName).path, O_RDONLY)
            guard descriptor >= 0 else {
                problems.append("the lock file of \(directory.path) is missing")
                continue
            }
            guard flock(descriptor, LOCK_SH) == 0 else {
                let code = errno
                close(descriptor)
                throw Failure(description: "The copy \(directory.path) could not be locked: \(String(cString: strerror(code))).")
            }
            guard fileManager.fileExists(atPath: marker) else {
                close(descriptor)
                problems.append("the copy \(directory.path) was removed while it was being locked")
                continue
            }
            let copiedKey = try contentKey(of: bundle)
            guard copiedKey == key else {
                close(descriptor)
                problems.append("the copy \(directory.path) has the content key \(copiedKey) instead of \(key)")
                _ = removeDirectoryIfUnused(directory)
                continue
            }
            let removed = removeUnusedCopies(in: root, keeping: directory)
            return Copy(bundle: bundle, directory: directory, key: key, created: created, removedDirectories: removed, lockDescriptor: descriptor)
        }
        throw Failure(description: "No usable copy of \(source.path) was prepared in \(root.path) after \(preparationAttempts) attempts: \(problems.joined(separator: "; ")).")
    }

    static func createCopy(of source: URL, at directory: URL, in root: URL) throws -> Bool {
        let fileManager = FileManager.default
        let staging = root.appendingPathComponent("\(stagingPrefix)\(getpid())-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        let bundle = staging.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        guard copyfile(source.path, bundle.path, nil, copyfile_flags_t(COPYFILE_CLONE | COPYFILE_RECURSIVE)) == 0 else {
            let code = errno
            try? fileManager.removeItem(at: staging)
            throw Failure(description: "The bundle \(source.path) could not be copied to \(bundle.path): \(String(cString: strerror(code))).")
        }
        guard fileManager.createFile(atPath: staging.appendingPathComponent(lockFileName).path, contents: nil),
              fileManager.createFile(atPath: staging.appendingPathComponent(completeMarkerName).path, contents: Data(source.path.utf8)) else {
            try? fileManager.removeItem(at: staging)
            throw Failure(description: "The lock and completion files could not be written in \(staging.path).")
        }
        if rename(staging.path, directory.path) == 0 { return true }
        let code = errno
        try? fileManager.removeItem(at: staging)
        if code == EEXIST || code == ENOTEMPTY { return false }
        throw Failure(description: "The copy \(staging.path) could not be moved to \(directory.path): \(String(cString: strerror(code))).")
    }

    static func removeUnusedCopies(in root: URL, keeping kept: URL) -> [String] {
        let fileManager = FileManager.default
        let entries = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var removed: [String] = []
        for entry in entries where entry.lastPathComponent != kept.lastPathComponent {
            if entry.lastPathComponent.hasPrefix(stagingPrefix) {
                let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
                if Date().timeIntervalSince(modified) > stagingLifetimeSeconds, (try? fileManager.removeItem(at: entry)) != nil {
                    removed.append(entry.lastPathComponent)
                }
            } else if removeDirectoryIfUnused(entry) {
                removed.append(entry.lastPathComponent)
            }
        }
        return removed
    }

    static func removeDirectoryIfUnused(_ directory: URL) -> Bool {
        let descriptor = open(directory.appendingPathComponent(lockFileName).path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
        return (try? FileManager.default.removeItem(at: directory)) != nil
    }
}
