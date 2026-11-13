
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
            guard let selection = try await AreaCaptureSelection.shared.select(allInOne: true, delaySeconds: UpshotPreferences.captureDelaySeconds,
                                                                              includeWindowShadow: UpshotPreferences.captureWindowShadow) else { return nil }
            if selection.recognizesText {
                lastAllInOneDispatchedWithoutScreenshot = true
                AppLog.event("capture", "all_in_one_capture_text_requested", fields: ["delay_seconds": String(describing: selection.delaySeconds)])
                guard let image = try await ScreenshotManager.shared.image(for: selection, delaySeconds: selection.delaySeconds) else { return nil }
                await recognizeAndCopyText(in: image)
                return nil
            }
            switch selection.kind {
            case .recording:
                lastAllInOneDispatchedWithoutScreenshot = true
                AppLog.event("capture", "all_in_one_recording_controls_requested")
                RecordingBarPresenter.shared.showPicker()
                return nil
            case .scrolling:
                return await captureScrollingAwaiting(selection: selection)
            case .area, .element, .window, .fullscreen:
                guard let url = try await ScreenshotManager.shared.capture(selection, includeShadow: UpshotPreferences.captureWindowShadow,
                                                                           delaySeconds: selection.delaySeconds) else { return nil }
                return await processAndFinishCapture(url: url, displayID: ScreenshotManager.shared.lastAreaCaptureDisplayID, source: ScreenshotManager.shared.lastAreaCaptureSource)
            }
        } catch {
            AppLog.event("capture", "all_in_one_capture_failed", fields: ["error": AppLog.error(error)])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }

    @discardableResult
    func captureScrollingAwaiting(selection: AreaCaptureSelectionResult? = nil) async -> URL? {
        guard let result = await ScrollingCaptureSession.shared.capture(selection: selection) else { return nil }
        return await processAndFinishCapture(url: result.url, displayID: result.displayID, source: result.source)
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
        let displayID = ScreenshotManager.shared.lastAreaCaptureDisplayID
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
            AppLog.event("capture", "capture_text_capture_failed", fields: ["error": AppLog.error(error)])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return .captureFailed
        }
        return await recognizeAndCopyText(in: image)
    }

    @discardableResult
    private func recognizeAndCopyText(in image: CGImage) async -> CaptureTextOutcome {
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: true)
        let text: String
        do {
            text = try await ImageTextRecognizer.recognizeText(in: image)
        } catch {
            AppLog.event("capture", "capture_text_recognition_failed", fields: ["error": AppLog.error(error)])
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
        let operationID = UUID().uuidString
        let started = ContinuousClock.now
        let metadata = ScreenshotManager.shared.lastCaptureMetadata
        do {
            let processedURL = try await ScreenshotOutputService.processCapture(
                at: url, captureType: metadata.captureType, appName: source?.appName ?? "Upshot",
                displayID: displayID, captureBounds: metadata.bounds, sourceScale: metadata.sourceScale,
                cursor: metadata.cursor, skipBackgroundPreset: metadata.skipBackgroundPreset, capturedAt: metadata.capturedAt
            )
            let result = finishCapture(url: processedURL, displayID: displayID, source: source, presentsPreview: presentsPreview)
            AppLog.event("capture", "capture_completed", fields: ["operation_id": operationID, "type": metadata.captureType.rawValue, "outcome": "success", "duration": String(describing: started.duration(to: .now))])
            return result
        } catch {
            AppLog.event("capture", "capture_completed", fields: ["operation_id": operationID, "type": metadata.captureType.rawValue, "outcome": "failed", "error": AppLog.error(error), "duration": String(describing: started.duration(to: .now))])
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
