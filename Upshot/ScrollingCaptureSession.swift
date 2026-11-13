import AppKit

enum ScrollingCaptureActions {
    static func start() {
        Task { await CaptureCoordinator.shared.captureScrollingAwaiting() }
    }
}

@MainActor
final class ScrollingCaptureSession {
    struct Result {
        let url: URL
        let displayID: CGDirectDisplayID?
        let source: CaptureSource?
    }

    static let shared = ScrollingCaptureSession()

    private var active = false
    private var identifier = UUID()
    private var panel: ScrollingCaptureControlPanel?
    private var continuation: CheckedContinuation<Result?, Never>?
    private var task: Task<Void, Never>?
    private var processor = ScrollingCaptureProcessor()
    private var frameSource: ScrollingCaptureFrameSource?
    private var autoScroll: ScrollingCaptureAutoScroll?
    private var geometry: [ScrollingCaptureFrameSource.Geometry] = []
    private var rect = CGRect.zero
    private var source: CaptureSource?
    private var height = 0
    private var stopRequested = false
    private var finishing = false
    private var maximumLengthReached = false

    func capture(selection: AreaCaptureSelectionResult? = nil) async -> Result? {
        guard !active, !Task.isCancelled else { return nil }
        active = true
        let identifier = UUID()
        self.identifier = identifier
        defer {
            task?.cancel()
            task = nil
            panel?.close()
            panel = nil
            frameSource = nil
            autoScroll = nil
            geometry.removeAll()
            source = nil
            processor = ScrollingCaptureProcessor()
            active = false
        }
        do {
            let selected: AreaCaptureSelectionResult
            if let selection { selected = selection }
            else {
                guard let selection = try await AreaCaptureSelection.shared.select(scrolling: true) else { return nil }
                selected = selection
            }
            rect = selected.rect
            source = selected.source
            geometry = selected.snapshots.map { .init(displayID: $0.displayID, frame: $0.frame, scale: $0.scale) }
            guard rect.height * (geometry.filter { $0.frame.intersects(rect) }.map(\.scale).max() ?? 1) >= 8 else {
                throw ScrollingCaptureError.invalidImage
            }
            height = 0
            stopRequested = false
            finishing = false
            maximumLengthReached = false
            autoScroll = ScrollingCaptureAutoScroll(rect: rect)
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    if Task.isCancelled { complete(nil); return }
                    let panel = ScrollingCaptureControlPanel(rect: rect)
                    panel.onStart = { [weak self] mode in self?.start(mode: mode) }
                    panel.onStop = { [weak self] in self?.stop() }
                    panel.onCancel = { [weak self] in self?.cancel() }
                    self.panel = panel
                    panel.show()
                    NSLog("Scrolling capture controls opened: x=%.1f y=%.1f width=%.1f height=%.1f", rect.minX, rect.minY, rect.width, rect.height)
                }
            } onCancel: {
                Task { @MainActor in
                    if self.identifier == identifier { self.cancel() }
                }
            }
        } catch {
            NSLog("Scrolling capture failed: %@", error.localizedDescription)
            CaptureTextFeedbackPresenter.shared.showFailure(title: error.localizedDescription,
                                                          displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }

    private func start(mode: ScrollingCaptureControlPanel.Mode) {
        guard continuation != nil, task == nil, !finishing, !maximumLengthReached else { return }
        if mode == .automatic, !CGPreflightPostEventAccess(), !CGRequestPostEventAccess() {
            update(status: "Enable Accessibility for Auto-Scroll, or choose Manual.", running: false)
            NSLog("Scrolling capture auto-scroll unavailable: event posting permission denied")
            return
        }
        stopRequested = false
        update(status: mode == .manual ? "Scroll down slowly inside the selected area. Stop saves the image." : "Auto-Scroll is running. Stop saves the image.", running: true)
        NSLog("Scrolling capture started: mode=%@", mode == .manual ? "manual" : "automatic")
        let identifier = identifier
        task = Task { [weak self] in
            guard let self else { return }
            await run(mode: mode)
            if self.identifier == identifier { task = nil }
        }
    }

    private func run(mode: ScrollingCaptureControlPanel.Mode) async {
        do {
            guard let panel else { return }
            if frameSource == nil {
                let prepared = try await ScrollingCaptureFrameSource(rect: rect, geometry: geometry, panelID: panel.windowID)
                try Task.checkCancellation()
                frameSource = prepared
            }
            guard let frameSource else { return }
            if height == 0 {
                let update = try await captureFrame()
                if update.kind == .maximumLengthReached { return }
                self.update(status: "Capture started. Stop saves the image.", running: true)
            }
            var unchangedFrames = 0
            var failedFrames = 0
            while !Task.isCancelled && !stopRequested {
                if mode == .automatic {
                    try postScroll(in: frameSource.rect)
                    try await Task.sleep(for: .milliseconds(400))
                } else {
                    try await Task.sleep(for: .milliseconds(180))
                }
                try Task.checkCancellation()
                do {
                    let update = try await captureFrame()
                    if stopRequested { break }
                    if update.kind == .maximumLengthReached { return }
                    failedFrames = 0
                    unchangedFrames = update.kind == .unchanged ? unchangedFrames + 1 : 0
                    if update.kind == .reversed {
                        if mode == .automatic { throw ScrollingCaptureError.unverifiedOverlap }
                        self.update(status: "Scroll down past the captured content to continue.", running: true)
                    } else {
                        self.update(status: mode == .manual ? "Scroll down slowly. Stop saves the image." : "Auto-Scroll is running. Stop saves the image.", running: true)
                    }
                    if mode == .automatic && unchangedFrames >= 4 {
                        NSLog("Scrolling capture auto-scroll reached end: height=%ld", height)
                        stopRequested = true
                    }
                } catch ScrollingCaptureError.unverifiedOverlap {
                    failedFrames += 1
                    update(status: "Waiting for matching content. Scroll slowly.", running: true)
                    if mode == .automatic || failedFrames >= 3 { throw ScrollingCaptureError.unverifiedOverlap }
                }
            }
            try Task.checkCancellation()
            if stopRequested { await save() }
        } catch is CancellationError {
        } catch ScrollingCaptureError.maximumLengthReached {
            guard !Task.isCancelled, continuation != nil else { return }
            reachMaximumLength()
        } catch let error as ScrollingCaptureAutoScroll.Failure {
            guard !Task.isCancelled, continuation != nil else { return }
            NSLog("Scrolling capture auto-scroll stopped: window=%u height=%ld reason=%@", autoScroll?.windowID ?? 0, height, error.localizedDescription)
            update(status: "\(error.localizedDescription) Stop saves captured content.", running: false)
        } catch {
            guard !Task.isCancelled, continuation != nil else { return }
            if stopRequested && height > 0 {
                NSLog("Scrolling capture final frame skipped: %@", error.localizedDescription)
                await save()
            } else {
                NSLog("Scrolling capture paused: height=%ld error=%@", height, error.localizedDescription)
                update(status: error.localizedDescription, running: false)
            }
        }
    }

    private func captureFrame() async throws -> ScrollingCaptureStitcher.Update {
        guard let frameSource else { throw ScrollingCaptureError.invalidImage }
        let image = try await frameSource.captureFrame()
        try Task.checkCancellation()
        let result = try await processor.append(image)
        try Task.checkCancellation()
        height = result.height
        if result.addedRows > 0 {
            NSLog("Scrolling capture frame verified: kind=%@ addedRows=%ld overlapRows=%ld meanError=%.6f height=%ld",
                  result.kind.rawValue, result.addedRows, result.overlapRows, result.meanError, height)
        }
        if result.kind == .maximumLengthReached { reachMaximumLength() }
        return result
    }

    private func reachMaximumLength() {
        maximumLengthReached = true
        NSLog("Scrolling capture maximum length reached: height=%ld maximumHeight=%ld maximumPixels=%ld", height,
              ScrollingCaptureOutputLimits.maximumHeight, ScrollingCaptureOutputLimits.maximumPixelCount)
        update(status: "Maximum length reached", running: false)
    }

    private func postScroll(in rect: CGRect) throws {
        guard CGPreflightPostEventAccess(), let panel, let autoScroll else {
            throw ScrollingCaptureError.unverifiedOverlap
        }
        try autoScroll.scroll(in: rect, excluding: panel.frame)
    }

    private func stop() {
        guard continuation != nil, !finishing else { return }
        stopRequested = true
        update(status: "Finishing scrolling capture…", running: true, finishing: true)
        NSLog("Scrolling capture stop requested: height=%ld", height)
        if task == nil {
            let identifier = identifier
            task = Task { [weak self] in
                guard let self else { return }
                await save()
                if self.identifier == identifier { task = nil }
            }
        }
    }

    private func save() async {
        guard continuation != nil, !finishing else { return }
        finishing = true
        update(status: "Saving scrolling capture…", running: true, finishing: true)
        do {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let name = ScreenshotFileNaming.fileName()
            let url = ScreenshotFileNaming.uniqueURL(fileName: name, in: directory)
            let scale = frameSource?.scale ?? 1
            let saved = try await processor.writePNG(to: url, scale: scale)
            if Task.isCancelled {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                throw CancellationError()
            }
            guard continuation != nil else { return }
            AreaSelectionMemory.rememberScreenshot(rect: rect)
            NSLog("Scrolling capture saved: pixels=%ldx%ld frames=%ld scale=%.2f file=%@", saved.width, saved.height, saved.frameCount, scale, url.lastPathComponent)
            complete(Result(url: url, displayID: frameSource?.displayID, source: source))
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, continuation != nil else { return }
            finishing = false
            NSLog("Scrolling capture save failed: %@", error.localizedDescription)
            update(status: "Save failed. Press Stop to retry, or Cancel.", running: false)
        }
    }

    private func cancel() {
        guard continuation != nil else { return }
        NSLog("Scrolling capture cancelled: discardedHeight=%ld", height)
        task?.cancel()
        complete(nil)
    }

    private func complete(_ result: Result?) {
        guard let continuation else { return }
        self.continuation = nil
        panel?.close()
        continuation.resume(returning: result)
    }

    private func update(status: String, running: Bool, finishing: Bool = false) {
        panel?.update(height: height, status: status, running: running, hasFrames: height > 0,
                      finishing: finishing, canStart: !maximumLengthReached)
    }
}
