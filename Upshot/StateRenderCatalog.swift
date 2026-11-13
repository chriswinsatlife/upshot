import AppKit
import SwiftUI
import Vision

struct StateRenderAppKitView: NSViewRepresentable {
    let makeView: () -> NSView
    func makeNSView(context: Context) -> NSView { makeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum StateRenderCatalog {
    static func states(fixtures: StateRenderFixtures) -> [StateRenderDefinition] {
        var states: [StateRenderDefinition] = []
        func add(_ name: String, _ source: String, _ marker: String, _ width: CGFloat, _ height: CGFloat,
                 scroll: CGFloat? = nil, _ view: @escaping () async throws -> AnyView) {
            states.append(StateRenderDefinition(name, source: source, marker: marker,
                                                 size: CGSize(width: width, height: height), scroll: scroll, makeView: view))
        }
        for tab in SettingsTab.allCases {
            add("settings-\(tab.rawValue)", "SettingsView", "struct SettingsView", 1000, 820) {
                SettingsNavigation.shared.selectedTab = tab
                return AnyView(SettingsView())
            }
            if tab != .about {
                add("settings-\(tab.rawValue)-expanded", "SettingsView", "struct SettingsView", 1000, tab == .screenshots ? 3500 : tab == .general ? 2300 : 1800) {
                    SettingsNavigation.shared.selectedTab = tab
                    UpshotStorage.defaults.set(true, forKey: UpshotPreferences.recordingDoNotDisturbKey)
                    UpshotStorage.defaults.set(true, forKey: UpshotPreferences.screenshotApplyBackgroundPresetKey)
                    UpshotStorage.defaults.set(WindowScreenshotBackgroundMode.customWallpaper.rawValue, forKey: UpshotPreferences.screenshotWindowBackgroundKey)
                    return AnyView(SettingsView())
                }
            }
        }
        add("settings-shortcuts-expanded", "CaptureHotkeySettingsSection", "struct CaptureHotkeySettingsSection", 860, 4200) {
            AnyView(InterfaceFormPage { CaptureHotkeySettingsSection(actions: CaptureHotkeyAction.allCases) }.environment(SettingsPermissions()))
        }
        let textRecognitionVariants: [(String, String, Bool, Bool)] = [
            ("", "", false, true),
            ("-language-unavailable", "xx-YY", true, true),
            ("-analysis-off", "", false, false)
        ]
        for (suffix, language, detectCodes, analyzeCaptures) in textRecognitionVariants {
            add("settings-text-recognition\(suffix)", "SettingsTextRecognitionPane", "struct SettingsTextRecognitionPane", 800, 640) {
                UpshotStorage.defaults.set(language, forKey: UpshotPreferences.recognitionLanguageKey)
                UpshotStorage.defaults.set(detectCodes, forKey: UpshotPreferences.recognitionDetectCodesKey)
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.recognitionKeepLineBreaksKey)
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.recognitionDetectLinksKey)
                UpshotStorage.defaults.set(analyzeCaptures, forKey: UpshotPreferences.libraryAnalyzeCapturesKey)
                UpshotStorage.defaults.set(false, forKey: UpshotPreferences.librarySortExistingKey)
                return AnyView(NavigationStack { SettingsTextRecognitionPane().navigationTitle("Text Recognition") })
            }
        }
        let sections: [(String, String, () -> AnyView)] = [
            ("area-selection", "AreaSelectionSettingsSection", { AnyView(InterfaceFormPage { AreaSelectionSettingsSection() }) }),
            ("screenshot-output", "ScreenshotOutputSettingsSection", { AnyView(InterfaceFormPage { ScreenshotOutputSettingsSection() }) }),
            ("annotation-editor", "AnnotationEditorSettingsSection", { AnyView(InterfaceFormPage { AnnotationEditorSettingsSection() }) }),
            ("capture-history", "CaptureHistorySettingsSection", { AnyView(InterfaceFormPage { CaptureHistorySettingsSection() }) }),
            ("live-recording", "LiveRecordingSettingsSection", { AnyView(InterfaceFormPage { LiveRecordingSettingsSection() }) }),
            ("recording-export", "RecordingExportSettingsSection", { AnyView(InterfaceFormPage { RecordingExportSettingsSection() }) }),
            ("quick-access", "QuickAccessSettingsSection", { AnyView(InterfaceFormPage { QuickAccessSettingsSection() }) }),
            ("after-screenshot", "AfterCaptureSettingsSection", { AnyView(InterfaceFormPage { AfterCaptureActionsSection(type: .screenshot, title: "After Capture") }) }),
            ("after-recording", "AfterCaptureSettingsSection", { AnyView(InterfaceFormPage { AfterCaptureActionsSection(type: .recording, title: "After Recording") }) }),
            ("configuration", "AutomationSettingsSection", { AnyView(InterfaceFormPage { AutomationSettingsSection() }) })
        ]
        for (name, source, view) in sections {
            add("settings-section-\(name)-expanded", source, "struct ", 860, name == "screenshot-output" ? 1450 : 900) {
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.screenshotApplyBackgroundPresetKey)
                UpshotStorage.defaults.set(WindowScreenshotBackgroundMode.customWallpaper.rawValue, forKey: UpshotPreferences.screenshotWindowBackgroundKey)
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.recordingDoNotDisturbKey)
                return view()
            }
        }
        for variant in ["grid", "list", "empty", "search", "search-empty", "inspector", "multi-selection", "screenshots", "recordings"] {
            add("library-\(variant)", "CaptureLibraryView", "struct CaptureLibraryView", 1280, 850) {
                let model = CaptureLibraryModel.shared
                model.installRenderItems(variant == "empty" ? [] : fixtures.items)
                UpshotStorage.defaults.set(variant == "list" ? "list" : "grid", forKey: "captureLibrary.layout")
                UpshotStorage.defaults.set(variant == "inspector" || variant == "multi-selection", forKey: "captureLibrary.inspectorVisible")
                if variant == "inspector", let item = fixtures.items.first(where: { !$0.isVideo }) { model.selection = [item.id] }
                if variant == "multi-selection" { model.selection = Set(fixtures.items.prefix(2).map(\.id)) }
                if variant == "screenshots" { model.scope = .kind(.screenshots) }
                if variant == "recordings" { model.scope = .kind(.recordings) }
                if variant.hasPrefix("search") { model.searchText = variant == "search" ? "Release" : "No matching capture" }
                return AnyView(CaptureLibraryView())
            }
        }
        for tool in AnnotationTool.allCases {
            add("annotation-tool-\(tool.rawValue)", "AnnotationEditorWindow", "struct AnnotationEditorWindow", 1280, 900) {
                AnyView(AnnotationEditorWindow(url: .constant(fixtures.screenshots[0]), renderModel: fixtures.annotationModel(tool: tool)))
            }
        }
        for variant in ["clean", "crop", "background", "border", "progressive-blur", "watermark", "camera", "color-adjustments"] {
            add("annotation-\(variant)", "AnnotationEditorWindow", "struct AnnotationEditorWindow", 1280, variant == "background" ? 2000 : 900,
                scroll: ["watermark", "color-adjustments"].contains(variant) ? 1 : variant == "camera" ? 0.6 : nil) {
                let model = fixtures.annotationModel(tool: .select, annotated: variant != "clean")
                if variant != "clean" && variant != "crop" { model.backgroundSettings.style = .gradient(AnnotationBackgroundGradient.presets[0]) }
                if variant == "camera" { model.backgroundSettings.camera.tiltXDegrees = 15; model.backgroundSettings.camera.tiltYDegrees = -12 }
                if variant == "crop" { model.beginCropping() }
                if variant == "border" || variant == "background" { model.backgroundSettings.border.isEnabled = true }
                if variant == "progressive-blur" || variant == "background" { model.backgroundSettings.progressiveBlur.isEnabled = true }
                if variant == "watermark" || variant == "background" { model.backgroundSettings.watermark.isEnabled = true; model.backgroundSettings.watermark.text = "Design Review" }
                return AnyView(AnnotationEditorWindow(url: .constant(fixtures.screenshots[0]), renderModel: model))
            }
        }
        add("background-picker", "AnnotationBackgroundInspector", "struct BackgroundPickerPopover", 360, 560) {
            AnyView(BackgroundPickerPopover(style: .constant(fixtures.annotationModel(tool: .select).backgroundSettings.style), rememberedWallpaper: nil,
                                           wallpaperStore: .shared, onPickWallpaper: {}, onSelectWallpaper: { _ in }, onPreview: { _, _ in }, onEndPreview: {}))
        }
        for variant in ["look", "zoom", "layout", "text", "redaction", "image", "audio", "captions", "transcript", "crop", "exporting", "export-failed", "share-failed"] {
            add("studio-\(variant)", "RecordingStudioWindow", "struct RecordingStudioContent", 1440, 1000) {
                let model = try await fixtures.studioModel()
                switch variant {
                case "zoom": model.selectedCueID = model.zoomCues.first?.id
                case "layout": model.selectedLayoutCueID = model.cameraLayoutCues.first?.id
                case "text": model.selectedTextID = model.textOverlays.first?.id
                case "redaction": model.selectedRedactionID = model.redactions.first?.id
                case "image": model.selectedImageID = model.imageOverlays.first?.id
                case "audio": model.selectedAudioClipID = model.audioClips.first?.id
                case "crop": model.beginVideoCrop()
                case "exporting": model.exportState = .exporting(progress: 0.42)
                case "export-failed": model.exportState = .failed("The export could not be completed.")
                case "share-failed": model.shareState = .failed("The upload could not be completed.")
                default: break
                }
                return AnyView(RecordingStudioContent(model: model).onDisappear { model.teardown() })
            }
        }
        for format in RecordingExportFormat.allCases {
            add("studio-export-options-\(format.rawValue.lowercased())", "RecordingExportOptions", "struct RecordingExportOptionsPopover", 380, 900) {
                var delivery = RecordingExportDeliveryOptions()
                delivery.format = format
                return AnyView(RecordingExportOptionsPopover(initialSettings: VideoCompressionSettings(), initialDeliveryOptions: delivery, onConfirm: { _ in }))
            }
        }
        add("studio-audio-export", "RecordingStudioInspector", "struct StudioAudioExportOptions", 300, 230) {
            AnyView(StudioAudioExportOptions(format: .constant(.m4a), onExport: {}))
        }
        add("share-options", "CloudUploadOptions", "struct CloudUploadOptionsPopover", 360, 300) {
            AnyView(CloudUploadOptionsPopover(suggestedTitle: "Release Overview", onConfirm: { _ in }))
        }
        for variant in ["one-card", "several-cards", "hover", "tucked", "compressing", "preparing", "link-copied", "upload-failed", "compressed", "action-failed", "video"] {
            add("quick-access-\(variant)", "CaptureShelfView", "struct CaptureShelfView", 380, variant == "several-cards" ? 670 : 400) {
                var cards = try fixtures.screenshots.prefix(variant == "several-cards" ? 4 : 1).map { url in
                    guard let image = NSImage(contentsOf: url) else { throw StateRenderFailure(message: "Fixture thumbnail could not be loaded") }
                    return ShelfItem(url: url, thumbnail: image)
                }
                guard !cards.isEmpty else { throw StateRenderFailure(message: "Fixture screenshots are unavailable") }
                switch variant {
                case "compressing": cards[0].activity = .compressing
                case "preparing": cards[0].activity = .preparing
                case "link-copied": cards[0].flash = .linkCopied
                case "upload-failed": cards[0].flash = .uploadFailed
                case "compressed": cards[0].flash = .compressed(summary: "Reduced by 42%")
                case "action-failed": cards[0].flash = .actionFailed(message: "The capture could not be saved.")
                case "video": cards[0].kind = .video
                default: break
                }
                CaptureShelf.shared.installRenderItems(cards, tucked: variant == "tucked")
                return AnyView(CaptureShelfView())
            }
        }
        for hover in [false, true] {
            add("pinned-screenshot\(hover ? "-hover" : "")", "PinnedScreenshotPresenter", "struct PinnedScreenshotView", 640, 400) {
                AnyView(PinnedScreenshotView(image: fixtures.image, url: fixtures.screenshots[0], onClose: {}))
            }
        }
        for filter in CaptureHistoryFilter.allCases {
            add("history-\(filter.rawValue)", "CaptureHistoryView", "struct CaptureHistoryView", 1140, 285) {
                let model = CaptureHistoryModel()
                model.installRenderItems(fixtures.items)
                model.filter = filter
                return AnyView(CaptureHistoryView(model: model))
            }
        }
        add("history-empty", "CaptureHistoryView", "struct CaptureHistoryView", 1140, 285) {
            AnyView(CaptureHistoryView(model: CaptureHistoryModel()))
        }
        for mode in AllInOneCaptureMode.allCases {
            add("selector-all-in-one-\(mode.rawValue)", "AreaCaptureSelection", "final class AreaCaptureSelectionView", 1000, 625) {
                guard let image = fixtures.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw StateRenderFailure(message: "Fixture selector image could not be decoded")
                }
                return AnyView(StateRenderAppKitView { AreaCaptureSelection.renderView(image: image, mode: mode, allInOne: true, crosshair: false) })
            }
        }
        for variant in ["area", "crosshair-magnifier", "window", "element"] {
            add("selector-\(variant)", "AreaCaptureSelection", "final class AreaCaptureSelectionView", 1000, 625) {
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.areaSelectionCrosshairKey)
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.areaSelectionMagnifierKey)
                guard let image = fixtures.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw StateRenderFailure(message: "Fixture selector image could not be decoded")
                }
                return AnyView(StateRenderAppKitView { AreaCaptureSelection.renderView(image: image, mode: variant == "window" ? .window : variant == "element" ? .element : .area, allInOne: false, crosshair: variant == "crosshair-magnifier") })
            }
        }
        for variant in ["manual-ready", "automatic-ready", "running", "finishing"] {
            add("scrolling-capture-\(variant)", "ScrollingCaptureControlPanel", "final class ScrollingCaptureControlPanel", 380, 195) {
                AnyView(StateRenderAppKitView { ScrollingCaptureControlPanel.renderContent(running: variant == "running", automatic: variant == "automatic-ready", finishing: variant == "finishing") })
            }
        }
        for variant in ["picker", "picker-teleprompter", "recording", "paused", "starting", "finishing", "picker-visible-windows", "picker-area"] {
            add("recording-bar-\(variant)", "RecordingBarPresenter", "struct RecordingBarView", 1000, variant == "picker-teleprompter" ? 430 : 190) {
                RecordingAreaSelectionPresenter.shared.installRenderSelection(active: variant == "picker-area", selected: variant == "picker-area", interacting: false)
                UpshotStorage.defaults.set(variant == "picker-visible-windows", forKey: UpshotPreferences.includeAppWindowsInCapturesKey)
                RecordingBarPresenter.shared.installRenderMode(recording: !variant.hasPrefix("picker"), teleprompter: variant == "picker-teleprompter")
                ScreenRecordingManager.shared.state = variant == "paused" ? .paused : variant == "starting" ? .starting : variant == "finishing" ? .finishing : .recording
                ScreenRecordingManager.shared.elapsedTime = 83
                return AnyView(RecordingBarView())
            }
        }
        for count in [3, 2, 1] {
            add("countdown-\(count)", "CaptureCountdownPresenter", "struct CaptureCountdownView", 240, 240) {
                AnyView(CaptureCountdownView(model: CaptureCountdownModel(remaining: count, total: 3), onCancel: {}))
            }
        }
        for (name, symbol, title, detail) in [
            ("success", "text.viewfinder", "Copied 1 line", "Capture a clear view of the work."),
            ("empty", "text.viewfinder", "No text found", "Nothing was recognized in that area."),
            ("failure", "exclamationmark.triangle", "Text recognition failed", "The capture succeeded, but text recognition failed.")
        ] {
            add("capture-text-\(name)", "CaptureTextFeedbackPresenter", "struct CaptureTextFeedbackView", 348, 100) {
                AnyView(CaptureTextFeedbackView(symbol: symbol, title: title, detail: detail, size: CGSize(width: 300, height: 52)))
            }
        }
        for variant in ["qr", "barcode", "links", "combined"] {
            add("capture-code-\(variant)", "CaptureCodeFeedbackPresenter", "struct CaptureCodeFeedbackView", 460, 400) {
                let codes = variant == "links" ? [] : [DetectedCaptureCode(symbology: variant == "barcode" ? "VNBarcodeSymbologyCode128" : VNBarcodeSymbology.qr.rawValue, payload: "https://example.com/review", data: nil)]
                let links = variant == "qr" || variant == "barcode" ? [] : [URL(string: "https://example.com/review")!]
                return AnyView(CaptureCodeFeedbackView(detection: CaptureCodeDetection(codes: codes, links: links), dismiss: {}))
            }
        }
        add("menu-bar", "MenuBarView", "struct MenuBarView", 400, 800) {
            AnyView(VStack(alignment: .leading, spacing: 10) { MenuBarView() }.buttonStyle(.borderless).padding(18))
        }
        return states + StateRenderSupplementalCatalog.states(fixtures: fixtures)
    }
}
