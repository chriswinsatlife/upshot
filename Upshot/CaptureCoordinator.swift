
import AppKit
import ImageIO
import ScreenCaptureKit
import SwiftUI

enum CaptureTextOutcome {
    case cancelled
    case noTextFound
    case captureFailed
    case recognitionFailed
    case copied(String)
}

@Observable
final class CaptureCoordinator {

    static let shared = CaptureCoordinator()

    var onShowPreview: ((URL, CGDirectDisplayID?, CaptureSource?) -> URL)?

    var onScrollingCaptureRequested: ((CGRect) -> Void)?
    private(set) var lastAllInOneDispatchedWithoutScreenshot = false

    private init() {}

    private var textCaptureInProgress = false


    func captureFullscreen() {
        Task { await performCaptureFullscreen() }
    }

    func captureWindow() {
        Task { await performCaptureWindow() }
    }

    func captureArea() {
        Task { await performCaptureArea() }
    }

    func captureAllInOne() {
        Task { await captureAllInOneAwaiting() }
    }

    @discardableResult
    func captureAllInOneAwaiting() async -> URL? {
        lastAllInOneDispatchedWithoutScreenshot = false
        do {
            guard let selection = try await AreaCaptureSelection.shared.select(allInOne: true) else { return nil }
            switch selection.kind {
            case .recording:
                lastAllInOneDispatchedWithoutScreenshot = true
                NSLog("All-In-One recording controls requested")
                RecordingBarPresenter.shared.showPicker()
                return nil
            case .scrolling:
                lastAllInOneDispatchedWithoutScreenshot = true
                if let onScrollingCaptureRequested {
                    NSLog("All-In-One scrolling capture dispatched")
                    onScrollingCaptureRequested(selection.rect)
                } else {
                    NSLog("All-In-One scrolling capture placeholder selected")
                    CaptureTextFeedbackPresenter.shared.showFailure(title: "Scrolling capture is not available yet", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
                }
                return nil
            case .area, .element, .window, .fullscreen:
                guard let url = try await ScreenshotManager.shared.capture(selection, includeShadow: UpshotPreferences.captureWindowShadow,
                                                                           delaySeconds: UpshotPreferences.captureDelaySeconds) else { return nil }
                return await processAndFinishCapture(url: url, displayID: ScreenshotManager.shared.lastAreaCaptureDisplayID, source: ScreenshotManager.shared.lastAreaCaptureSource)
            }
        } catch {
            NSLog("All-In-One capture failed: %@", String(describing: error))
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }

    func captureSmartElement() {
        Task { await captureSmartElementAwaiting() }
    }

    @discardableResult
    func captureSmartElementAwaiting() async -> URL? {
        guard let url = await ScreenshotManager.shared.captureArea(includeShadow: UpshotPreferences.captureWindowShadow,
                                                                  delaySeconds: UpshotPreferences.captureDelaySeconds,
                                                                  smartElement: true) else { return nil }
        return await processAndFinishCapture(url: url, displayID: ScreenshotManager.shared.lastAreaCaptureDisplayID, source: ScreenshotManager.shared.lastAreaCaptureSource)
    }

    func capturePreviousArea() {
        Task { await capturePreviousAreaAwaiting() }
    }

    @discardableResult
    func capturePreviousAreaAwaiting() async -> URL? {
        guard let url = await ScreenshotManager.shared.capturePreviousArea(delaySeconds: UpshotPreferences.captureDelaySeconds) else { return nil }
        return await processAndFinishCapture(url: url, displayID: ScreenshotManager.shared.lastAreaCaptureDisplayID, source: ScreenshotManager.shared.lastAreaCaptureSource)
    }

    func captureText() {
        Task { await performCaptureText() }
    }


    @discardableResult
    func captureFullscreenAwaiting() async -> URL? {
        await performCaptureFullscreen()
    }

    @discardableResult
    func captureWindowAwaiting() async -> URL? {
        await performCaptureWindow()
    }

    @discardableResult
    func captureAreaAwaiting() async -> URL? {
        await performCaptureArea()
    }

    func captureAreaAwaiting(delaySeconds: Int, presentsPreview: Bool) async -> URL? {
        guard let url = await ScreenshotManager.shared.captureArea(
            includeShadow: UpshotPreferences.captureWindowShadow,
            delaySeconds: delaySeconds
        ) else { return nil }
        return await processAndFinishCapture(url: url, displayID: ScreenshotManager.shared.lastAreaCaptureDisplayID,
                                             source: ScreenshotManager.shared.lastAreaCaptureSource, presentsPreview: presentsPreview)
    }

    @discardableResult
    func captureTextAwaiting() async -> CaptureTextOutcome {
        await performCaptureText()
    }

    @discardableResult
    private func performCaptureFullscreen() async -> URL? {
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
        CaptureShelfPresenter.shared.setTargetDisplay(displayID)

        guard await CaptureCountdownPresenter.shared.runIfNeeded(
            seconds: UpshotPreferences.captureDelaySeconds,
            displayID: displayID
        ) else { return nil }
        let probe = CaptureSourceProbe(tracksPointer: false)
        let source = probe.finish(.display(displayID))
        guard let url = await ScreenshotManager.shared.captureFullscreen(displayID: displayID) else { return nil }
        return await processAndFinishCapture(url: url, displayID: displayID, source: source)
    }

    @discardableResult
    private func performCaptureWindow() async -> URL? {
        let captured = await ScreenshotManager.shared.captureWindow(
            includeShadow: UpshotPreferences.captureWindowShadow,
            delaySeconds: UpshotPreferences.captureDelaySeconds
        )
        let source = ScreenshotManager.shared.lastAreaCaptureSource
        guard let url = captured else { return nil }
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: true)
        return await processAndFinishCapture(url: url, displayID: displayID, source: source)
    }

    @discardableResult
    private func performCaptureArea() async -> URL? {
        let captured = await ScreenshotManager.shared.captureArea(
            includeShadow: UpshotPreferences.captureWindowShadow,
            delaySeconds: UpshotPreferences.captureDelaySeconds
        )
        let source = ScreenshotManager.shared.lastAreaCaptureSource
        guard let url = captured else { return nil }
        let displayID = ScreenshotManager.shared.lastAreaCaptureDisplayID
        return await processAndFinishCapture(url: url, displayID: displayID, source: source)
    }

    @discardableResult
    private func performCaptureText() async -> CaptureTextOutcome {
        guard !textCaptureInProgress else { return .cancelled }
        textCaptureInProgress = true
        defer { textCaptureInProgress = false }
        let image: CGImage
        do {
            guard let selected = try await TextCaptureSelection().select() else { return .cancelled }
            image = selected

        } catch {
            NSLog("Capture Text capture failed: %@", String(describing: error))
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return .captureFailed
        }

        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: true)
        let text: String
        do {
            text = try await ImageTextRecognizer.recognizeText(in: image)
        } catch {
            NSLog("Capture Text recognition failed: %@", String(describing: error))
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Text recognition failed", displayID: displayID)
            return .recognitionFailed
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            CaptureTextFeedbackPresenter.shared.showNoTextFound(displayID: displayID)
            if UpshotPreferences.playSounds {
                NSSound.beep()
            }
            return .noTextFound
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        CaptureTextFeedbackPresenter.shared.showCopied(text: text, displayID: displayID)
        if UpshotPreferences.playSounds {
            CaptureFeedbackSound.play()
        }
        return .copied(text)
    }

    func recordFullscreen(_ display: SCDisplay) {
        Task {
            guard await CaptureCountdownPresenter.shared.runIfNeeded(
                seconds: UpshotPreferences.recordingStartDelaySeconds,
                displayID: display.displayID
            ) else { return }
            ScreenRecordingManager.shared.startRecording(source: ScreenRecordingSource(kind: .fullscreen(display)))
        }
    }

    func recordWindow(_ window: SCWindow) {
        Task {
            let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: true)
            guard await CaptureCountdownPresenter.shared.runIfNeeded(
                seconds: UpshotPreferences.recordingStartDelaySeconds,
                displayID: displayID
            ) else { return }
            ScreenRecordingManager.shared.startRecording(source: ScreenRecordingSource(kind: .window(window)))
        }
    }

    func recordArea(_ display: SCDisplay, rect: CGRect) {
        Task {
            guard await CaptureCountdownPresenter.shared.runIfNeeded(
                seconds: UpshotPreferences.recordingStartDelaySeconds,
                displayID: display.displayID
            ) else { return }
            ScreenRecordingManager.shared.startRecording(
                source: ScreenRecordingSource(kind: .area(display: display, rect: rect))
            )
        }
    }


    @discardableResult
    @MainActor
    private func processAndFinishCapture(url: URL, displayID: CGDirectDisplayID?, source: CaptureSource?, presentsPreview: Bool = true) async -> URL? {
        let metadata = ScreenshotManager.shared.lastCaptureMetadata
        do {
            let processedURL = try await ScreenshotOutputService.processCapture(
                at: url, captureType: metadata.captureType, appName: source?.appName ?? "Upshot",
                displayID: displayID, captureBounds: metadata.bounds, sourceScale: metadata.sourceScale,
                cursor: metadata.cursor, skipBackgroundPreset: metadata.skipBackgroundPreset, capturedAt: metadata.capturedAt
            )
            return finishCapture(url: processedURL, displayID: displayID, source: source, presentsPreview: presentsPreview)
        } catch {
            NSLog("Screenshot output integration failed; raw capture retained file=%@ error=%@", url.path, error.localizedDescription)
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: displayID)
            return nil
        }
    }

    @discardableResult
    private func finishCapture(url: URL, displayID: CGDirectDisplayID?, source: CaptureSource?, presentsPreview: Bool) -> URL {
        if UpshotPreferences.playSounds {
            CaptureFeedbackSound.play()
        }
        let historyURL = presentsPreview
            ? showPreview(url: url, displayID: displayID, source: source)
            : ScreenshotHistoryStore.shared.importScreenshot(from: url, source: source)
        if UpshotPreferences.recognitionDetectCodes {
            Task { await CaptureCodeActions.detectCodes(at: historyURL, displayID: displayID) }
        }
        return historyURL
    }

    @discardableResult
    private func showPreview(url: URL, displayID: CGDirectDisplayID?, source: CaptureSource?) -> URL {
        guard let onShowPreview else {
            let historyURL = ScreenshotHistoryStore.shared.importScreenshot(from: url, source: source)
            CaptureShelf.shared.add(url: historyURL)
            if AfterCaptureActions.isEnabled(.showOverlay, for: .screenshot) {
                CaptureShelfPresenter.shared.show(displayID: displayID)
            }
            return historyURL
        }

        return onShowPreview(url, displayID, source)
    }
}

@MainActor
private enum CaptureFeedbackSound {
    private static let sound: NSSound? = {
        let url = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif")
        return NSSound(contentsOf: url, byReference: true)
    }()

    static func play() {
        guard let sound else { return }

        sound.stop()
        sound.currentTime = 0
        sound.play()
    }
}
