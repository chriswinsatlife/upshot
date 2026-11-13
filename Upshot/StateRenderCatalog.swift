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
        for tab in SettingsTab.allCases where tab != .quickAccess {
            add("settings-\(tab.rawValue)", "SettingsView", "struct SettingsView", 1000, 820) {
                SettingsNavigation.shared.prepareRenderState(selectedTab: tab)
                return AnyView(SettingsView())
            }
            if tab != .about, tab != .shortcuts {
                add("settings-\(tab.rawValue)-expanded", "SettingsView", "struct SettingsView", 1000, tab == .screenshots ? 2000 : tab == .general ? 820 : 1800) {
                    SettingsNavigation.shared.prepareRenderState(selectedTab: tab)
                    UpshotStorage.defaults.set(true, forKey: UpshotPreferences.recordingDoNotDisturbKey)
                    UpshotStorage.defaults.set(true, forKey: UpshotPreferences.screenshotApplyBackgroundPresetKey)
                    UpshotStorage.defaults.set(WindowScreenshotBackgroundMode.customWallpaper.rawValue, forKey: UpshotPreferences.screenshotWindowBackgroundKey)
                    return AnyView(SettingsView())
                }
            }
        }
        for variant in ["default", "enabled"] {
            add(variant == "default" ? "settings-annotate" : "settings-annotate-\(variant)", "SettingsAnnotatePane", "struct SettingsAnnotatePane", 800, 620) {
                if variant == "enabled" {
                    for key in [UpshotPreferences.annotationInverseArrowDirectionKey, UpshotPreferences.annotationObjectShadowsKey,
                                UpshotPreferences.annotationAutomaticallyExpandCanvasKey, UpshotPreferences.annotationEditorAlwaysOnTopKey] {
                        UpshotStorage.defaults.set(true, forKey: key)
                    }
                    UpshotStorage.defaults.set(UpshotPreferences.startingToolLastUsed, forKey: UpshotPreferences.annotationStartingToolKey)
                    UpshotStorage.defaults.set(false, forKey: UpshotPreferences.lowResolutionEditorPreviewKey)
                }
                return AnyView(NavigationStack { SettingsAnnotatePane().navigationTitle("Annotate") })
            }
        }
        for variant in ["", "-expanded", "-shortcuts-access-required"] {
            add("settings-quick-access\(variant)", "SettingsQuickAccessPane", "struct SettingsQuickAccessPane", 800, variant == "-expanded" ? 1340 : 820) {
                if variant == "-expanded" {
                    UpshotStorage.defaults.set(10, forKey: UpshotPreferences.previewAutoCloseSecondsKey)
                    UpshotStorage.defaults.set(QuickAccessAutoCloseAction.saveAndClose.rawValue, forKey: UpshotPreferences.previewAutoCloseActionKey)
                    UpshotStorage.defaults.set(true, forKey: UpshotPreferences.previewMoveToActiveScreenKey)
                }
                let pane = variant == "-shortcuts-access-required" ? SettingsQuickAccessPane(accessibilityGranted: false) : SettingsQuickAccessPane()
                return AnyView(NavigationStack { pane.navigationTitle("Quick Access") })
            }
        }
        add("settings-section-screenshot-output-jpeg-transparent-expanded", "ScreenshotOutputSettingsSection", "struct ScreenshotOutputSettingsSection", 860, 820) {
            UpshotStorage.defaults.set(ScreenshotExportFormat.jpeg.rawValue, forKey: UpshotPreferences.exportFormatKey)
            UpshotStorage.defaults.set(true, forKey: UpshotPreferences.autoCompressKey)
            UpshotStorage.defaults.set(WindowScreenshotBackgroundMode.transparent.rawValue, forKey: UpshotPreferences.screenshotWindowBackgroundKey)
            return AnyView(InterfaceFormPage { ScreenshotOutputSettingsSection(); WindowScreenshotSettingsSection(); ScreenshotBackgroundPresetSettingsSection() })
        }
        add("settings-shortcuts-expanded", "SettingsShortcutsPane", "struct SettingsShortcutsPane", 860, 4260) {
            AnyView(SettingsShortcutsPane(model: fixtures.shortcutSettingsModel(customizesAllInOne: true)))
        }
        for variant in ["search", "search-empty", "recording", "conflict", "registration-failure"] {
            add("settings-shortcuts-\(variant)", "SettingsShortcutsPane", "struct SettingsShortcutsPane", 800, 640) {
                let model = fixtures.shortcutSettingsModel()
                let searchText = variant == "search" ? "record" : variant == "search-empty" ? "Upload to Dropbox" : ""
                if variant == "recording" { model.presentRecordingForRendering(.area) }
                if variant == "conflict" {
                    model.presentRejectionForRendering(CaptureHotkeySettingsModel.conflictMessage(for: StateRenderFixtures.allInOneShortcut, conflict: .allInOne), for: .previousArea)
                }
                if variant == "registration-failure" {
                    model.presentRejectionForRendering("⌃⌥Space could not be registered. It may be used by another app. Choose a different shortcut.", for: .window)
                }
                return AnyView(NavigationStack { SettingsShortcutsPane(model: model, searchText: searchText).navigationTitle("Shortcuts") })
            }
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
            ("screenshot-output", "ScreenshotOutputSettingsSection", { AnyView(InterfaceFormPage { ScreenshotOutputSettingsSection(); WindowScreenshotSettingsSection(); ScreenshotBackgroundPresetSettingsSection() }) }),
            ("live-recording", "LiveRecordingSettingsSection", { AnyView(InterfaceFormPage { LiveRecordingSettingsSection() }) }),
            ("recording-export", "RecordingExportSettingsSection", { AnyView(InterfaceFormPage { RecordingExportSettingsSection() }) }),
            ("after-screenshot", "AfterCaptureSettingsSection", { AnyView(InterfaceFormPage { AfterCaptureActionsSection(type: .screenshot, title: "After Capture") }) }),
            ("after-recording", "AfterCaptureSettingsSection", { AnyView(InterfaceFormPage { AfterCaptureActionsSection(type: .recording, title: "After Recording") }) })
        ]
        for (name, source, view) in sections {
            add("settings-section-\(name)-expanded", source, "struct ", 860, name == "screenshot-output" ? 820 : 900) {
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.screenshotApplyBackgroundPresetKey)
                UpshotStorage.defaults.set(WindowScreenshotBackgroundMode.customWallpaper.rawValue, forKey: UpshotPreferences.screenshotWindowBackgroundKey)
                UpshotStorage.defaults.set(true, forKey: UpshotPreferences.recordingDoNotDisturbKey)
                return view()
            }
        }
        let advancedStates: [(String, Int, String?)] = [
            ("settings-advanced", 0, nil),
            ("settings-advanced-history-one-week", 7, nil),
            ("settings-advanced-history-custom", 10, nil),
            ("settings-advanced-configuration-failure", 0, "[preferences]\nplaySounds = yes\n")
        ]
        for (name, retentionDays, configurationText) in advancedStates {
            add(name, "SettingsAdvancedPane", "struct SettingsAdvancedPane", 800, 420) {
                UpshotStorage.defaults.set(retentionDays, forKey: UpshotPreferences.historyRetentionDaysKey)
                if let configurationText {
                    try Data(configurationText.utf8).write(to: UpshotStorage.configurationFileURL)
                    AutomationConfiguration.shared.synchronize()
                }
                return AnyView(SettingsAdvancedPane())
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
            add("studio-export-options-\(format.rawValue.lowercased())", "RecordingExportOptions", "struct RecordingExportOptionsPopover", 360, format == .gif ? 460 : 640) {
                var delivery = RecordingExportDeliveryOptions()
                delivery.format = format
                return AnyView(RecordingExportOptionsPopover(initialSettings: VideoCompressionSettings(), initialDeliveryOptions: delivery, onConfirm: { _ in }))
            }
        }
        add("studio-audio-export", "RecordingStudioInspector", "struct StudioAudioExportOptions", 320, 180) {
            AnyView(StudioAudioExportOptions(format: .constant(.m4a), onExport: {}))
        }
        add("share-options", "CloudUploadOptions", "struct CloudUploadOptionsPopover", 360, 220) {
            AnyView(CloudUploadOptionsPopover(suggestedTitle: "Release Overview", onConfirm: { _ in }))
        }
        for variant in ["sharing", "exported"] {
            add("studio-\(variant)", "RecordingStudioActions", "struct StudioActionFooter", 1440, 1000) {
                let model = try await fixtures.studioModel()
                CloudCredentialStore.shared.workerURL = "https://share.example.com"
                CloudCredentialStore.shared.uploadToken = "render-state"
                if variant == "sharing" {
                    model.shareState = .rendering(progress: 0.64)
                } else {
                    model.exportState = .finished(fixtures.screenshots[0].deletingLastPathComponent().appendingPathComponent("Capture Walkthrough.mov"))
                }
                return AnyView(RecordingStudioContent(model: model).onDisappear {
                    CloudCredentialStore.shared.workerURL = ""
                    CloudCredentialStore.shared.uploadToken = ""
                    model.teardown()
                })
            }
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
        func historyOverDesktop(_ view: some View) -> AnyView {
            AnyView(view.background {
                Image(nsImage: fixtures.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            })
        }
        for filter in CaptureHistoryFilter.allCases {
            add("history-\(filter.rawValue)", "CaptureHistoryView", "struct CaptureHistoryView", 1140, CaptureHistoryStrip.preferredHeight) {
                let model = CaptureHistoryModel()
                model.installRenderItems(fixtures.items)
                model.filter = filter
                return historyOverDesktop(CaptureHistoryView(model: model))
            }
        }
        add("history-selection-moved", "CaptureHistoryView", "struct CaptureHistoryView", 1140, CaptureHistoryStrip.preferredHeight) {
            let model = CaptureHistoryModel()
            model.installRenderItems(fixtures.items)
            model.moveSelection(by: 2)
            return historyOverDesktop(CaptureHistoryView(model: model))
        }
        add("history-restore-failed", "CaptureHistoryView", "struct CaptureHistoryView", 1140, CaptureHistoryStrip.preferredHeight) {
            let model = CaptureHistoryModel()
            model.installRenderItems(fixtures.items)
            model.errorMessage = "The capture could not be restored. The file may have moved or become unreadable."
            return historyOverDesktop(CaptureHistoryView(model: model))
        }
        add("history-empty", "CaptureHistoryView", "struct CaptureHistoryView", 1140, CaptureHistoryStrip.preferredHeight) {
            historyOverDesktop(CaptureHistoryView(model: CaptureHistoryModel()))
        }
        add("history-empty-filter", "CaptureHistoryView", "struct CaptureHistoryView", 1140, CaptureHistoryStrip.preferredHeight) {
            let model = CaptureHistoryModel()
            model.installRenderItems(fixtures.items.filter(CaptureHistoryFilter.screenshots.includes))
            model.filter = .gifs
            return historyOverDesktop(CaptureHistoryView(model: model))
        }
        add("history-loading", "CaptureHistoryView", "struct CaptureHistoryStrip", 1140, CaptureHistoryStrip.preferredHeight) {
            historyOverDesktop(CaptureHistoryStrip(
                filter: .constant(.all), selectedID: .constant(nil), items: [], isLoading: true,
                errorMessage: nil, restore: {}, close: {}
            ))
        }
        for mode in AllInOneCaptureMode.allCases {
            add("selector-all-in-one-\(mode.rawValue)", "AreaCaptureSelection", "final class AreaCaptureSelectionView", 1000, 625) {
                guard let image = fixtures.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw StateRenderFailure(message: "Fixture selector image could not be decoded")
                }
                return AnyView(StateRenderAppKitView { AreaCaptureSelection.renderView(image: image, mode: mode, allInOne: true, crosshair: false) })
            }
        }
        for variant in ["aspect", "narrow", "no-selection", "status"] {
            let size = variant == "narrow" ? CGSize(width: 700, height: 625) : CGSize(width: 1000, height: 625)
            add("selector-all-in-one-\(variant)", "AreaCaptureSelection", "final class AreaCaptureSelectionView", size.width, size.height) {
                guard let image = fixtures.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw StateRenderFailure(message: "Fixture selector image could not be decoded")
                }
                return AnyView(StateRenderAppKitView {
                    AreaCaptureSelection.renderView(image: image, mode: variant == "status" ? .previousArea : .area, allInOne: true, crosshair: variant == "no-selection" || variant == "status", size: size,
                                                    aspect: variant == "aspect" ? RecordingAreaAspect(16, 9) : nil,
                                                    status: variant == "status" ? "No previous screenshot area" : nil)
                })
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
        for variant in ["magnifier-above", "magnifier-below", "area-default"] {
            add("selector-\(variant)", "AreaCaptureSelection", "final class AreaCaptureSelectionView", 1000, 625) {
                UpshotStorage.defaults.set(variant != "area-default", forKey: UpshotPreferences.areaSelectionCrosshairKey)
                UpshotStorage.defaults.set(variant != "area-default", forKey: UpshotPreferences.areaSelectionMagnifierKey)
                guard let image = fixtures.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw StateRenderFailure(message: "Fixture selector image could not be decoded")
                }
                let selection = variant == "magnifier-above" ? CGRect(x: 120, y: 60, width: 500, height: 230) : variant == "magnifier-below" ? CGRect(x: 120, y: 330, width: 500, height: 230) : nil
                let pointer = selection.map { CGPoint(x: $0.maxX, y: variant == "magnifier-above" ? $0.maxY : $0.minY) }
                return AnyView(StateRenderAppKitView { AreaCaptureSelection.renderView(image: image, mode: .area, allInOne: false, crosshair: false, pointer: pointer, selection: selection) })
            }
        }
        for renderState in ScrollingCaptureControlPanel.RenderState.allCases {
            add("scrolling-capture-\(renderState.rawValue)", "ScrollingCaptureControlPanel", "final class ScrollingCaptureControlPanel", 640, 230) {
                AnyView(Image(nsImage: fixtures.image).resizable().aspectRatio(contentMode: .fill).overlay { ScrollingCaptureControlPanel.renderView(renderState) }.clipped())
            }
        }
        for variant in ["picker", "picker-teleprompter", "recording", "paused", "starting", "finishing", "picker-visible-windows", "picker-area", "picker-area-empty", "picker-area-teleprompter", "flyout", "flyout-hover-gif"] {
            let showsArea = variant.hasPrefix("picker-area") || variant.hasPrefix("flyout")
            let isTall = showsArea || variant.hasSuffix("teleprompter")
            add("recording-bar-\(variant)", "RecordingBarPresenter", "struct RecordingBarView", BarMetrics.panelWidth, isTall ? BarMetrics.panelHeight : 200) {
                RecordingAreaSelectionPresenter.shared.installRenderSelection(active: showsArea, selected: showsArea && variant != "picker-area-empty", interacting: false)
                UpshotStorage.defaults.set(variant == "picker-visible-windows", forKey: UpshotPreferences.includeAppWindowsInCapturesKey)
                RecordingBarPresenter.shared.installRenderMode(
                    recording: !variant.hasPrefix("picker") && !variant.hasPrefix("flyout"),
                    teleprompter: variant.hasSuffix("teleprompter"),
                    hoveredOutputMode: variant == "flyout-hover-gif" ? .gif : nil
                )
                ScreenRecordingManager.shared.state = variant == "paused" ? .paused : variant == "starting" ? .starting : variant == "finishing" ? .finishing : .recording
                ScreenRecordingManager.shared.elapsedTime = 83
                guard variant.hasPrefix("flyout") else { return AnyView(RecordingBarView()) }
                return AnyView(RecordingBarView().background { Image(nsImage: fixtures.image).resizable().scaledToFill() }.clipped())
            }
        }
        for count in [3, 2, 1] {
            add("countdown-\(count)", "CaptureCountdownPresenter", "struct CaptureCountdownView", 240, 240) {
                AnyView(CaptureCountdownView(model: CaptureCountdownModel(remaining: count, total: 3), onCancel: {}))
            }
        }
        for (name, feedback) in CaptureFeedbackRenderStates.textFeedback {
            add("capture-text-\(name)", "CaptureTextFeedbackPresenter", "struct CaptureTextFeedbackView", 560, 150) {
                AnyView(CaptureFeedbackRenderBackdrop(image: fixtures.image) { CaptureTextFeedbackView(feedback: feedback) })
            }
        }
        for variant in CaptureFeedbackRenderStates.codeVariants {
            add("capture-code-\(variant)", "CaptureCodeFeedbackPresenter", "struct CaptureCodeFeedbackView", 520, variant == "many" ? 500 : 340) {
                AnyView(CaptureFeedbackRenderBackdrop(image: fixtures.image) { CaptureFeedbackRenderStates.codeFeedbackView(variant: variant) })
            }
        }
        return states + StateRenderSupplementalCatalog.states(fixtures: fixtures)
    }
}
