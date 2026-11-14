import AppKit
import ImageIO
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
    let placement: StateRenderPlacement
    let scroll: StateRenderScroll
    let displaySize: CGSize
    let windowTitle: String?
    var makeAlert: (() -> NSAlert)? = nil
    let makeView: () async throws -> AnyView

    init(_ name: String, source: String, marker: String, size: CGSize, scroll: CGFloat? = nil,
         displaySize: CGSize = StateRenderDisplay.standardSize, windowTitle: String? = nil, makeAlert: (() -> NSAlert)? = nil, makeView: @escaping () async throws -> AnyView) {
        self.name = name
        sourceFile = "Upshot/\(source).swift"
        line = StateRenderSource.line(in: sourceFile, containing: marker)
        self.size = size
        (placement, self.scroll) = StateRenderPlacement.resolve(name: name, scrollFraction: scroll)
        self.displaySize = displaySize
        self.windowTitle = windowTitle
        self.makeAlert = makeAlert
        self.makeView = makeView
    }
}

final class StateRenderWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        StateRenderer.lower(childWin, to: level)
        super.addChildWindow(childWin, ordered: place)
    }
}

struct StateRenderWindowSafety: Equatable {
    let className: String
    let windowNumber: Int
    let level: Int
    let isVisible: Bool
    let serverLayer: Int?
    let isOnscreen: Bool

    init(_ window: NSWindow) {
        className = String(describing: type(of: window))
        windowNumber = window.windowNumber
        level = window.level.rawValue
        isVisible = window.isVisible
        let info = windowNumber > 0
            ? (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(windowNumber)) as? [[String: Any]])?.first
            : nil
        serverLayer = info?[kCGWindowLayer as String] as? Int
        isOnscreen = info?[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    var failures: [String] {
        var failures: [String] = []
        if isVisible, level >= StateRenderer.desktopLevel {
            failures.append("window \(windowNumber) \(className) is visible at level \(level), not below the desktop level \(StateRenderer.desktopLevel)")
        }
        if isOnscreen, let serverLayer, serverLayer >= StateRenderer.desktopLevel {
            failures.append("window \(windowNumber) \(className) is on screen at window-server layer \(serverLayer), not below the desktop layer \(StateRenderer.desktopLevel)")
        }
        return failures
    }

    var description: String {
        "\(className) number=\(windowNumber) level=\(level) visible=\(isVisible) serverLayer=\(serverLayer.map(String.init) ?? "none") onscreen=\(isOnscreen)"
    }

    var fields: [String: Any] {
        ["class": className, "windowNumber": windowNumber, "level": level, "visible": isVisible,
         "serverLayer": serverLayer ?? NSNull(), "onscreen": isOnscreen]
    }
}

struct StateRenderDisplaySafety: Equatable {
    static let prohibitedPolicy = NSApplication.ActivationPolicy.prohibited.rawValue
    static let policyRereadLimit = 25
    static let policyRereadMicroseconds: useconds_t = 1000

    let cachedActivationPolicy: Int
    let activationPolicy: Int
    let policyRereads: Int
    let isActive: Bool
    let windows: [StateRenderWindowSafety]

    init() {
        cachedActivationPolicy = NSApp.activationPolicy().rawValue
        var policy = cachedActivationPolicy
        var rereads = 0
        while policy != Self.prohibitedPolicy, rereads < Self.policyRereadLimit {
            usleep(Self.policyRereadMicroseconds)
            rereads += 1
            policy = NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)?.activationPolicy.rawValue ?? policy
        }
        activationPolicy = policy
        policyRereads = rereads
        isActive = NSApp.isActive
        windows = NSApp.windows.map { StateRenderWindowSafety($0) }
    }

    var failures: [String] {
        var failures: [String] = []
        if activationPolicy != Self.prohibitedPolicy {
            failures.append("activation policy is \(activationPolicy) after \(policyRereads) rereads and was \(cachedActivationPolicy) in NSApp, not prohibited \(Self.prohibitedPolicy)")
        }
        if isActive { failures.append("the app is active") }
        return failures + windows.flatMap(\.failures)
    }

    var description: String {
        "policy=\(activationPolicy) cachedPolicy=\(cachedActivationPolicy) policyRereads=\(policyRereads) active=\(isActive) windows=\(windows.map(\.description).joined(separator: "; "))"
    }
}

struct StateRenderEntry: Codable {
    let name: String
    let state: String
    let appearance: String
    let scrollFrame: Int?
    let sourceFile: String
    let line: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Int
    let captureMethod: String
    let windowLevel: Int
    let desktopWindowLevel: Int
    let wallpaper: String
    let filename: String
}

struct StateRenderManifest: Codable {
    let states: [StateRenderEntry]
    let isolationVerified: Bool
    let defaultsSuite: String
    let statesPerAppearance: Int
    let displaySize: [Int]
    let contactSheet: String
}

enum StateRenderer {
    static var isRequested: Bool { UpshotStorage.isRenderingStates }
    static var scenario = ""
    static var fixtureVideoURL: URL?
    nonisolated static let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
    nonisolated static var renderLevel: NSWindow.Level { NSWindow.Level(rawValue: desktopLevel - 1) }
    static let captureMethod = "screenCaptureKitDisplayFrame"
    static let frameworkDefaults: [String: Any] = ["AVDesktopPlaybackControlsControllerShowsDurationInsteadOfTimeRemainingDefaultsKey": true]
    private static var definitionsByName: [String: StateRenderDefinition] = [:]

    static let usage = "Usage: Upshot --render-states DIRECTORY [--state NAME]\n       Upshot --present-live-state NAME\n       Upshot --list-live-states\n"

    struct Selection {
        let state: String
        let appearance: String?
        let scrollFrame: Int?

        init(_ requested: String) {
            var name = requested
            var appearance: String?
            for candidate in ["light", "dark"] where name.hasSuffix("-" + candidate) {
                appearance = candidate
                name.removeLast(candidate.count + 1)
            }
            var scrollFrame: Int?
            if let range = name.range(of: "-scroll-", options: .backwards), let number = Int(name[range.upperBound...]) {
                scrollFrame = number
                name = String(name[..<range.lowerBound])
            }
            state = name
            self.appearance = appearance
            self.scrollFrame = scrollFrame
        }
    }

    static func run() -> Never {
        if UpshotStorage.isPresentingLiveState || UpshotStorage.isListingLiveStates { StateRenderLivePresentation.run() }
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        guard let path = arguments.first, !path.hasPrefix("--"),
              arguments.count == 1 || (arguments.count == 3 && arguments[1] == "--state") else {
            FileHandle.standardError.write(Data(usage.utf8))
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
                AppLog.event("rendering", "state_renderer", fields: ["error": AppLog.error(error), "outcome": "failed"])
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
            UpshotStorage.defaults.removePersistentDomain(forName: UpshotStorage.defaultsSuiteName)
            if let root = UpshotStorage.fixtureRoot { try? FileManager.default.removeItem(at: root) }
        }
        let definitions = try await loadDefinitions()
        let selection = requested.map(Selection.init)
        let selected = definitions.filter { selection == nil || selection?.state == $0.name }
        guard !selected.isEmpty else { throw StateRenderFailure(message: "Unknown state: \(requested ?? "")") }
        let inventory = selected.map { ["state": $0.name, "sourceFile": $0.sourceFile, "line": String($0.line), "status": "pending"] }
        try JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("catalog.json"), options: .atomic)
        AppLog.event("rendering", "state_renderer_started", fields: ["activationPolicy": "prohibited", "statesPerAppearance": String(describing: selected.count)])
        var entries: [StateRenderEntry] = []
        for appearance in ["light", "dark"] where selection?.appearance == nil || selection?.appearance == appearance {
            for definition in selected {
                let started = Date()
                let captured = try await capture(definition, appearance: appearance, onlyScrollFrame: selection?.scrollFrame, output: output)
                entries += captured
                FileHandle.standardError.write(Data("rendered state=\(definition.name) appearance=\(appearance) frames=\(captured.count) seconds=\(String(format: "%.2f", Date().timeIntervalSince(started)))\n".utf8))
            }
        }
        let completedInventory = selected.map { definition in
            ["state": definition.name, "sourceFile": definition.sourceFile, "line": String(definition.line), "status": "rendered",
             "frames": entries.filter { $0.state == definition.name && $0.appearance == "light" }.map(\.name).joined(separator: ",")]
        }
        try JSONSerialization.data(withJSONObject: completedInventory, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("catalog.json"), options: .atomic)
        try contactSheet(entries: entries, output: output)
        UserDefaults.standard.synchronize()
        try await Task.sleep(for: .seconds(2))
        try isolation.verify(to: output)
        let manifest = StateRenderManifest(states: entries, isolationVerified: true,
                                          defaultsSuite: UpshotStorage.defaultsSuiteName,
                                          statesPerAppearance: selected.count,
                                          displaySize: [Int(StateRenderDisplay.size.width), Int(StateRenderDisplay.size.height)],
                                          contactSheet: "contact_sheet.png")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        AppLog.event("rendering", "state_renderer", fields: ["contactSheet": "contact_sheet.png", "images": String(describing: entries.count), "isolation": "verified", "outcome": "success"])
        print("Rendered \(entries.count) PNGs to \(output.path)")
    }

    static func loadDefinitions() async throws -> [StateRenderDefinition] {
        _ = try StateRenderDisplay.frame
        UserDefaults.standard.setVolatileDomain(StateRenderer.frameworkDefaults, forName: UserDefaults.argumentDomain)
        let fixtures = try await StateRenderFixtures.make()
        fixtureVideoURL = fixtures.project.screenURL
        try StateRenderDesktop.install(fixtureImage: fixtures.image)
        let definitions = StateRenderCatalog.states(fixtures: fixtures)
        let duplicateNames = Dictionary(grouping: definitions, by: \.name).filter { $0.value.count > 1 }.keys.sorted()
        guard duplicateNames.isEmpty else {
            throw StateRenderFailure(message: "Duplicate state names: \(duplicateNames.joined(separator: ", "))")
        }
        definitionsByName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        return definitions
    }

    private static func prepare(_ definition: StateRenderDefinition) async throws -> AnyView {
        scenario = definition.name
        StateRenderFixtures.resetPreferences()
        SettingsNavigation.shared.prepareRenderState(selectedTab: .general)
        return try await definition.makeView()
    }

    private static func context(named name: String, on stage: StateRenderStage) async throws -> NSWindow {
        guard let definition = definitionsByName[name], case .window(let kind) = definition.placement else {
            throw StateRenderFailure(message: "Unknown context window state \(name)")
        }
        let window = stage.addWindow(kind, view: try await prepare(definition))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    static func build(_ definition: StateRenderDefinition, on stage: StateRenderStage) async throws {
        switch definition.placement {
        case .window(let kind):
            let window = stage.addWindow(kind, view: try await prepare(definition))
            if let title = definition.windowTitle { window.title = title }
        case .panel(let panel):
            try stage.addPanel(panel, view: try await prepare(definition))
        case .display:
            try stage.addDisplay(view: try await prepare(definition))
        case .alert(let contextName):
            var context: NSWindow?
            if let contextName { context = try await self.context(named: contextName, on: stage) }
            scenario = definition.name
            guard let makeAlert = definition.makeAlert else { throw StateRenderFailure(message: "\(definition.name) has no alert") }
            stage.addAlert(makeAlert(), over: context)
        case .popover(let contextName, let anchor):
            let context = try await context(named: contextName, on: stage)
            try stage.addPopover(try await prepare(definition), over: context, anchor: anchor)
        case .panelOverContext(let contextName, let panel):
            let context = try await context(named: contextName, on: stage)
            try stage.addPanel(panel(context.frame), view: try await prepare(definition))
        case .panelOverDisplay(let backdrop, let panel):
            let view = try await prepare(definition)
            try stage.addDisplay(view: try backdrop())
            try stage.addPanel(panel, view: view)
        }
    }

    static func settle(_ stage: StateRenderStage, milliseconds: Int) async throws {
        for window in stage.windows { window.contentView?.layoutSubtreeIfNeeded() }
        try await Task.sleep(for: .milliseconds(milliseconds))
        for window in stage.windows {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if window.hasShadow { window.invalidateShadow() }
        }
    }

    static func scrollOffsets(_ scroll: NSScrollView?, mode: StateRenderScroll) -> [CGFloat?] {
        guard let scroll else { return [nil] }
        let range = StateRenderStage.scrollRange(scroll)
        let visible = scroll.contentView.bounds.height - scroll.contentInsets.top - scroll.contentInsets.bottom
        switch mode {
        case .top: return [nil]
        case .fraction(let fraction): return [range.lowerBound + (range.upperBound - range.lowerBound) * fraction]
        case .frames:
            guard range.upperBound - range.lowerBound > 2 else { return [nil] }
            let step = max(120, visible - 64)
            var offsets: [CGFloat] = [range.lowerBound]
            while let last = offsets.last, last < range.upperBound { offsets.append(min(range.upperBound, last + step)) }
            return offsets
        }
    }

    static func apply(offset: CGFloat, to scroll: NSScrollView) {
        guard let document = scroll.documentView else { return }
        let range = StateRenderStage.scrollRange(scroll)
        let y = document.isFlipped ? offset : range.upperBound - (offset - range.lowerBound)
        scroll.contentView.scroll(to: CGPoint(x: scroll.contentView.bounds.minX, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private static func capture(_ definition: StateRenderDefinition, appearance: String, onlyScrollFrame: Int?, output: URL) async throws -> [StateRenderEntry] {
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        StateRenderDisplay.size = definition.displaySize
        defer { StateRenderDisplay.size = StateRenderDisplay.standardSize }
        let stage = try StateRenderStage(appearance: appearance)
        try StateRenderDesktop.prepare(appearance: appearance)
        defer { stage.tearDown() }
        try verifyWindows()
        try await build(definition, on: stage)
        try verifyWindows()
        try await settle(stage, milliseconds: definition.name.hasPrefix("quick-look-") ? 1800 : 450)
        try await stage.addShadows()
        try await settle(stage, milliseconds: 120)
        let scrollView = stage.primaryScrollView()
        let offsets = scrollOffsets(scrollView, mode: definition.scroll)
        var entries: [StateRenderEntry] = []
        for (index, offset) in offsets.enumerated() {
            let frameNumber = offsets.count > 1 ? index + 1 : nil
            if let onlyScrollFrame, frameNumber != onlyScrollFrame { continue }
            if let offset, let scrollView {
                apply(offset: offset, to: scrollView)
                try await settle(stage, milliseconds: 160)
            }
            try verifyWindows()
            let (image, level) = try await stage.capture()
            try verifyWindows()
            let frameName = definition.name + (frameNumber.map { "-scroll-\($0)" } ?? "")
            let name = frameName + "-" + appearance
            let destination = output.appendingPathComponent(name + ".png")
            let bitmap = NSBitmapImageRep(cgImage: image)
            bitmap.size = StateRenderDisplay.size
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw StateRenderFailure(message: "PNG encoding failed for \(name)") }
            try png.write(to: destination, options: .atomic)
            AppLog.event("rendering", "state_renderer", fields: ["desktopLevel": String(describing: desktopLevel), "level": String(describing: level), "method": captureMethod, "outcome": "success", "width": String(describing: image.width), "state": name, "height": String(describing: image.height), "windows": String(describing: stage.windows.count)])
            entries.append(StateRenderEntry(name: name, state: definition.name, appearance: appearance, scrollFrame: frameNumber,
                                            sourceFile: definition.sourceFile, line: definition.line, pixelWidth: image.width,
                                            pixelHeight: image.height, scale: Int(StateRenderDisplay.scale), captureMethod: captureMethod,
                                            windowLevel: level, desktopWindowLevel: desktopLevel,
                                            wallpaper: StateRenderWallpaper.url(appearance: appearance).path, filename: name + ".png"))
        }
        return entries
    }

    static func lower(_ child: NSWindow, to level: NSWindow.Level) {
        if child.level.rawValue >= desktopLevel { child.level = level }
        child.ignoresMouseEvents = true
    }

    @discardableResult
    static func verifyWindows() throws -> StateRenderDisplaySafety {
        let safety = StateRenderDisplaySafety()
        let failures = safety.failures
        guard failures.isEmpty else {
            throw StateRenderFailure(message: "State renderer display safety invariant failed state=\(scenario) failed=\(failures.joined(separator: "; ")) \(safety.description)")
        }
        return safety
    }

    private static func contactSheet(entries: [StateRenderEntry], output: URL) throws {
        let columns = 6
        let cell = CGSize(width: 360, height: 280)
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
        for (index, entry) in entries.enumerated() { try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(output.appendingPathComponent(entry.filename) as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 720] as CFDictionary) else {
                throw StateRenderFailure(message: "Contact sheet image missing: \(entry.filename)")
            }
            let image = NSImage(cgImage: thumbnail, size: .zero)
            let origin = CGPoint(x: CGFloat(index % columns) * cell.width, y: size.height - CGFloat(index / columns + 1) * cell.height)
            let available = CGSize(width: cell.width - 24, height: cell.height - 52)
            let ratio = min(available.width / CGFloat(entry.pixelWidth), available.height / CGFloat(entry.pixelHeight))
            let imageSize = CGSize(width: CGFloat(entry.pixelWidth) * ratio, height: CGFloat(entry.pixelHeight) * ratio)
            image.draw(in: CGRect(x: origin.x + (cell.width - imageSize.width) / 2, y: origin.y + 40 + (available.height - imageSize.height) / 2, width: imageSize.width, height: imageSize.height))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (entry.name as NSString).draw(in: CGRect(x: origin.x + 6, y: origin.y + 6, width: cell.width - 12, height: 30),
                                          withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        } }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw StateRenderFailure(message: "Contact sheet encoding failed") }
        try data.write(to: output.appendingPathComponent("contact_sheet.png"), options: .atomic)
    }
}
