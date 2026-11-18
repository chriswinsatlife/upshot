import Darwin
import Foundation
import Testing
@testable import UyuniLiveState

struct LiveStatePrivateBundleTests {
    let workspace: URL
    let source: URL
    let root: URL

    init() throws {
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("UyuniLiveStatePrivateBundleTests-\(UUID().uuidString)", isDirectory: true)
        source = workspace.appendingPathComponent("Sample.app", isDirectory: true)
        root = workspace.appendingPathComponent("copies", isDirectory: true)
        let executables = source.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        try Data("first build".utf8).write(to: executables.appendingPathComponent("Sample"))
        try Data("<plist/>".utf8).write(to: source.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("Contents/Current").path, withDestinationPath: "MacOS")
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: workspace)
    }

    @Test func aBuildIsCopiedOnceAndEachProcessHoldsItsCopy() throws {
        defer { cleanUp() }
        let first = try LiveStatePrivateBundle.prepareCopy(of: source, in: root)
        let second = try LiveStatePrivateBundle.prepareCopy(of: source, in: root)
        defer { close(first.lockDescriptor); close(second.lockDescriptor) }
        #expect(first.created)
        #expect(!second.created)
        #expect(first.bundle == second.bundle)
        #expect(first.bundle.deletingLastPathComponent().deletingLastPathComponent() == root)
        #expect(try LiveStatePrivateBundle.contentKey(of: first.bundle) == LiveStatePrivateBundle.contentKey(of: source))
        #expect(try String(contentsOf: first.bundle.appendingPathComponent("Contents/MacOS/Sample"), encoding: .utf8) == "first build")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: first.bundle.appendingPathComponent("Contents/Current").path) == "MacOS")
        #expect(!LiveStatePrivateBundle.removeDirectoryIfUnused(first.directory))
    }

    @Test func aRebuiltBundleGetsANewCopyAndUnusedCopiesOfEarlierBuildsAreRemoved() throws {
        defer { cleanUp() }
        let first = try LiveStatePrivateBundle.prepareCopy(of: source, in: root)
        try Data("second build, longer".utf8).write(to: source.appendingPathComponent("Contents/MacOS/Sample"))
        let held = try LiveStatePrivateBundle.prepareCopy(of: source, in: root)
        #expect(held.directory != first.directory)
        #expect(held.removedDirectories.isEmpty)
        #expect(FileManager.default.fileExists(atPath: first.directory.path))
        close(first.lockDescriptor)
        let third = try LiveStatePrivateBundle.prepareCopy(of: source, in: root)
        defer { close(held.lockDescriptor); close(third.lockDescriptor) }
        #expect(third.directory == held.directory)
        #expect(third.removedDirectories == [first.directory.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: first.directory.path))
    }

    @Test func aCopyWhoseFilesDifferFromItsBuildIsReplaced() throws {
        defer { cleanUp() }
        let first = try LiveStatePrivateBundle.prepareCopy(of: source, in: root)
        close(first.lockDescriptor)
        try FileManager.default.removeItem(at: first.bundle.appendingPathComponent("Contents/Info.plist"))
        let replaced = try LiveStatePrivateBundle.prepareCopy(of: source, in: root)
        defer { close(replaced.lockDescriptor) }
        #expect(replaced.directory == first.directory)
        #expect(replaced.created)
        #expect(FileManager.default.fileExists(atPath: replaced.bundle.appendingPathComponent("Contents/Info.plist").path))
    }
}
