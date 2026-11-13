import AppKit
import SwiftUI

struct StateRenderFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct StateRenderDefinition {
    let name: String
    let sourceFile: String
    let line: Int
    let size: CGSize
    var scrollFraction: CGFloat? = nil
    let makeView: () async throws -> AnyView

    init(_ name: String, source: String, marker: String, size: CGSize, scroll: CGFloat? = nil,
         makeView: @escaping () async throws -> AnyView) {
        self.name = name
        sourceFile = "Upshot/\(source).swift"
        line = StateRenderSource.line(in: sourceFile, containing: marker)
        self.size = size
        scrollFraction = scroll
        self.makeView = makeView
    }
}

final class StateRenderWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct StateRenderEntry: Codable {
    let name: String
    let state: String
    let appearance: String
    let sourceFile: String
    let line: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Int
    let captureMethod: String
    let windowLevel: Int
    let desktopWindowLevel: Int
    let filename: String
}

struct StateRenderManifest: Codable {
    let states: [StateRenderEntry]
    let isolationVerified: Bool
    let defaultsSuite: String
    let statesPerAppearance: Int
    let contactSheet: String
}

enum StateRenderer {
    static var isRequested: Bool { UpshotStorage.isRenderingStates }
    static var scenario = ""
    static let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
    static var renderLevel: NSWindow.Level { NSWindow.Level(rawValue: desktopLevel - 1) }

    static func run() -> Never {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        guard let path = arguments.first, !path.hasPrefix("--"),
              arguments.count == 1 || (arguments.count == 3 && arguments[1] == "--state") else {
            FileHandle.standardError.write(Data("Usage: Upshot --render-states DIRECTORY [--state NAME]\n".utf8))
            exit(2)
        }
        let output = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
        let app = NSApplication.shared
        guard app.setActivationPolicy(.prohibited) else { exit(1) }
        Task { @MainActor in
            do {
                try await render(to: output, state: arguments.count == 3 ? arguments[2] : nil)
                exit(0)
            } catch {
                NSLog("State renderer outcome=failed error=%@", error.localizedDescription)
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        app.run()
        exit(1)
    }

    private static func render(to output: URL, state requested: String?) async throws {
        let isolation = try StateRenderIsolation()
        try isolation.validateOutput(output)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try isolation.writeSnapshot(to: output.appendingPathComponent("isolation-before.json"))
        defer {
            for window in NSApp.windows { window.orderOut(nil) }
            UpshotStorage.defaults.removePersistentDomain(forName: UpshotStorage.fixtureIdentifier)
            if let root = UpshotStorage.fixtureRoot { try? FileManager.default.removeItem(at: root) }
        }
        let fixtures = try await StateRenderFixtures.make()
        let definitions = StateRenderCatalog.states(fixtures: fixtures)
        guard Set(definitions.map(\.name)).count == definitions.count else {
            throw StateRenderFailure(message: "Duplicate state names")
        }
        let selected = definitions.filter { definition in
            requested == nil || requested == definition.name || requested == definition.name + "-light" || requested == definition.name + "-dark"
        }
        guard !selected.isEmpty else { throw StateRenderFailure(message: "Unknown state: \(requested ?? "")") }
        let inventory = selected.map { ["state": $0.name, "sourceFile": $0.sourceFile, "line": String($0.line), "status": "pending"] }
        try JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("catalog.json"), options: .atomic)
        NSLog("State renderer started statesPerAppearance=%ld activationPolicy=prohibited", selected.count)
        var entries: [StateRenderEntry] = []
        for appearance in ["light", "dark"] {
            for definition in selected where requested == nil || requested == definition.name || requested == definition.name + "-" + appearance {
                scenario = definition.name
                StateRenderFixtures.resetPreferences()
                let entry = try await capture(definition, appearance: appearance, output: output)
                entries.append(entry)
            }
        }
        let completedInventory = selected.map { ["state": $0.name, "sourceFile": $0.sourceFile, "line": String($0.line), "status": "rendered"] }
        try JSONSerialization.data(withJSONObject: completedInventory, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("catalog.json"), options: .atomic)
        try contactSheet(entries: entries, output: output)
        try isolation.verify(to: output)
        let manifest = StateRenderManifest(states: entries, isolationVerified: true,
                                          defaultsSuite: UpshotStorage.fixtureIdentifier,
                                          statesPerAppearance: selected.count, contactSheet: "contact_sheet.png")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        NSLog("State renderer outcome=success images=%ld isolation=verified contactSheet=contact_sheet.png", entries.count)
        print("Rendered \(entries.count) PNGs to \(output.path)")
    }

    private static func capture(_ definition: StateRenderDefinition, appearance: String, output: URL) async throws -> StateRenderEntry {
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let root = try await definition.makeView()
        let usesWindowChrome = ["settings-", "library-", "annotation-", "studio-"].contains { definition.name.hasPrefix($0) }
            && !definition.name.contains("-section-") && !definition.name.contains("options")
            && !definition.name.contains("audio-export") && !definition.name.contains("new-style")
            && !definition.name.contains("expanded") && !definition.name.contains("inspector-")
            && definition.size.height <= 1000
        let controller = NSHostingController(rootView: root
            .defaultAppStorage(UpshotStorage.defaults)
            .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
            .transaction { $0.disablesAnimations = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor)))
        controller.sizingOptions = []
        let host = controller.view
        let window = StateRenderWindow(contentRect: CGRect(origin: .zero, size: definition.size),
                                       styleMask: usesWindowChrome ? [.titled, .closable, .resizable, .fullSizeContentView] : [.borderless], backing: .buffered, defer: false)
        window.level = renderLevel
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.appearance = NSApp.appearance
        window.contentViewController = controller
        window.setFrame(CGRect(origin: .zero, size: definition.size), display: false)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try verifyWindows()
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(definition.name.hasPrefix("quick-look-") ? 1800 : 300))
        host.layoutSubtreeIfNeeded()
        if let fraction = definition.scrollFraction {
            scroll(host, fraction: fraction)
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
        }
        try verifyWindows()
        guard let windowInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]],
              let actualLevel = windowInfo.first?[kCGWindowLayer as String] as? Int,
              actualLevel < desktopLevel else {
            throw StateRenderFailure(message: "Could not verify below-desktop level for \(definition.name)")
        }
        let width = Int(definition.size.width * 2)
        let height = Int(definition.size.height * 2)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) else {
            throw StateRenderFailure(message: "Could not allocate \(definition.name)")
        }
        bitmap.size = definition.size
        window.appearance?.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw StateRenderFailure(message: "PNG encoding failed") }
        let name = definition.name + "-" + appearance
        let destination = output.appendingPathComponent(name + ".png")
        var captureMethod = "cacheDisplay"
        if CGPreflightScreenCaptureAccess() {
            window.sharingType = .readOnly
            let number = window.windowNumber
            let status = try await Task.detached {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-l", String(number), "-o", "-x", destination.path]
                capture.standardOutput = FileHandle.nullDevice
                capture.standardError = FileHandle.nullDevice
                try capture.run()
                capture.waitUntilExit()
                return capture.terminationStatus
            }.value
            guard status == 0, let captured = NSImage(contentsOf: destination),
                  let representation = captured.representations.first,
                  representation.pixelsWide == width, representation.pixelsHigh == height else {
                throw StateRenderFailure(message: "Window capture failed to produce 2x pixels for \(name)")
            }
            captureMethod = "window"
        } else {
            try png.write(to: destination, options: .atomic)
        }
        NSLog("State renderer state=%@ pixels=%ldx%ld level=%ld desktopLevel=%ld method=%@ outcome=success", name, width, height, actualLevel, desktopLevel, captureMethod)
        return StateRenderEntry(name: name, state: definition.name, appearance: appearance,
                                sourceFile: definition.sourceFile, line: definition.line, pixelWidth: width,
                                pixelHeight: height, scale: 2, captureMethod: captureMethod, windowLevel: actualLevel,
                                desktopWindowLevel: desktopLevel, filename: name + ".png")
    }

    private static func verifyWindows() throws {
        guard NSApp.activationPolicy() == .prohibited,
              NSApp.windows.allSatisfy({ $0.level.rawValue < desktopLevel || !$0.isVisible }) else {
            throw StateRenderFailure(message: "State renderer display safety invariant failed")
        }
    }

    private static func scroll(_ view: NSView, fraction: CGFloat) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: maximum * (document.isFlipped ? fraction : 1 - fraction)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        for child in view.subviews { scroll(child, fraction: fraction) }
    }

    private static func contactSheet(entries: [StateRenderEntry], output: URL) throws {
        let columns = 6
        let cell = CGSize(width: 360, height: 270)
        let rows = (entries.count + columns - 1) / columns
        let size = CGSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw StateRenderFailure(message: "Contact sheet allocation failed") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, entry) in entries.enumerated() {
            guard let image = NSImage(contentsOf: output.appendingPathComponent(entry.filename)) else { throw StateRenderFailure(message: "Contact sheet image missing: \(entry.filename)") }
            let origin = CGPoint(x: CGFloat(index % columns) * cell.width, y: size.height - CGFloat(index / columns + 1) * cell.height)
            let available = CGSize(width: cell.width - 24, height: cell.height - 52)
            let ratio = min(available.width / CGFloat(entry.pixelWidth), available.height / CGFloat(entry.pixelHeight))
            let imageSize = CGSize(width: CGFloat(entry.pixelWidth) * ratio, height: CGFloat(entry.pixelHeight) * ratio)
            image.draw(in: CGRect(x: origin.x + (cell.width - imageSize.width) / 2, y: origin.y + 40 + (available.height - imageSize.height) / 2, width: imageSize.width, height: imageSize.height))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (entry.name as NSString).draw(in: CGRect(x: origin.x + 6, y: origin.y + 6, width: cell.width - 12, height: 30),
                                          withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw StateRenderFailure(message: "Contact sheet encoding failed") }
        try data.write(to: output.appendingPathComponent("contact_sheet.png"), options: .atomic)
    }
}
