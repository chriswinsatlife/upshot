import AppKit
import AVFoundation
import SwiftUI

enum StateRenderSupplementalCatalog {
    static func states(fixtures: StateRenderFixtures) -> [StateRenderDefinition] {
        var states: [StateRenderDefinition] = []
        func add(_ name: String, _ source: String, _ marker: String, _ width: CGFloat, _ height: CGFloat,
                 windowTitle: String? = nil, _ view: @escaping () async throws -> AnyView) {
            states.append(StateRenderDefinition(name, source: source, marker: marker,
                                                 size: CGSize(width: width, height: height), windowTitle: windowTitle, makeView: view))
        }
        add("settings-general-permissions-denied", "SettingsGeneralPane", "struct SettingsGeneralPane", 1000, 820) {
            SettingsNavigation.shared.prepareRenderState(selectedTab: .general)
            return AnyView(SettingsView())
        }
        add("settings-sidebar-search", "SettingsView", "struct SettingsSearchEntry", 1000, 820) {
            SettingsNavigation.shared.prepareRenderState(selectedTab: .general, searchText: "record")
            return AnyView(SettingsView())
        }
        for variant in ["configured", "connected", "failed"] {
            add("settings-cloud-\(variant)", "SettingsCloudPane", "struct CloudSettingsPane", 1000, 1000) {
                SettingsNavigation.shared.prepareRenderState(selectedTab: .cloud)
                return AnyView(SettingsView())
            }
        }
        add("settings-mcp-disabled", "SettingsMCPPane", "struct MCPSettingsPane", 1000, 820) {
            UpshotStorage.defaults.set(false, forKey: UpshotPreferences.agentServerEnabledKey)
            SettingsNavigation.shared.prepareRenderState(selectedTab: .mcp)
            return AnyView(SettingsView())
        }
        add("settings-section-after-recording-upload-paused", "AfterCaptureSettingsSection", "struct AfterCaptureActionsSection", 860, 520) {
            UpshotStorage.defaults.set(true, forKey: AfterCaptureAction.upload.storageKey(for: .recording))
            SettingsNavigation.shared.prepareRenderState(selectedTab: .screenRecording, detail: AnyView(InterfaceFormPage { AfterCaptureActionsSection(type: .recording, title: "After Recording") }))
            return AnyView(SettingsView())
        }
        add("settings-mcp-failed", "SettingsMCPPane", "struct MCPSettingsPane", 1000, 820) {
            SettingsNavigation.shared.prepareRenderState(selectedTab: .mcp)
            return AnyView(SettingsView())
        }
        add("settings-mcp-copied", "SettingsMCPPane", "struct MCPSettingsPane", 1000, 820) {
            SettingsNavigation.shared.prepareRenderState(selectedTab: .mcp)
            return AnyView(SettingsView())
        }
        add("design-gallery", "InterfaceStyleGallery", "struct InterfaceStyleGallery", 1380, 2900) {
            AnyView(ScrollView { InterfaceStyleGallery(backdrop: fixtures.image) })
        }
        for variant in ["annotation", "studio"] {
            add("\(variant)-new-style", variant == "annotation" ? "AnnotationStyleStrip" : "RecordingStudioLook", "private var nameEditor", 340, 330) {
                if variant == "annotation" {
                    return AnyView(AnnotationStyleStrip(model: fixtures.annotationModel(tool: .select), presetStore: .shared, onEditorAction: {}).renderNameEditor)
                }
                let model = try await fixtures.studioModel()
                return AnyView(RecordingStudioStyleStrip(model: model, presetStore: .shared).renderNameEditor.onDisappear { model.teardown() })
            }
        }
        for variant in ["camera", "zoom", "cursor", "keystrokes", "audio", "clip"] {
            add("studio-page-\(variant)", "RecordingStudioInspector", "struct StudioInspector", 1440, 1000) {
                let model = try await fixtures.studioModel()
                return AnyView(RecordingStudioContent(model: model).onDisappear { model.teardown() })
            }
        }
        add("annotation-load-failed", "AnnotationEditorWindow", "struct AnnotationLoadFailureView", 1280, 900) {
            let model = AnnotationEditorModel()
            model.errorMessage = "The screenshot could not be opened."
            return AnyView(AnnotationEditorWindow(url: .constant(fixtures.screenshots[0]), renderModel: model))
        }
        let pinnedVariants: [(name: String, size: CGSize)] = [
            ("normal", CGSize(width: 560, height: 350)),
            ("hover", CGSize(width: 560, height: 350)),
            ("copied", CGSize(width: 560, height: 350)),
            ("square", CGSize(width: 560, height: 350)),
            ("no-border", CGSize(width: 560, height: 350)),
            ("small-hover", CGSize(width: 240, height: 150)),
            ("compact-hover", CGSize(width: 160, height: 100)),
            ("minimum-hover", CGSize(width: 128, height: 80))
        ]
        for variant in pinnedVariants {
            add("pinned-\(variant.name)", "PinnedScreenshotPresenter", "struct PinnedScreenshotView", variant.size.width + 80, variant.size.height + 80) {
                UpshotStorage.defaults.set(variant.name != "square", forKey: UpshotPreferences.pinnedScreenshotRoundedCornersKey)
                UpshotStorage.defaults.set(variant.name != "no-border", forKey: UpshotPreferences.pinnedScreenshotBorderKey)
                let isDark = NSApp.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return AnyView(
                    PinnedScreenshotView(image: isDark ? fixtures.image : try fixtures.windowAreaImage(), url: fixtures.screenshots[0], onClose: {})
                        .frame(width: variant.size.width, height: variant.size.height)
                )
            }
        }
        for state in MenuBarMenuRenderState.allCases {
            add(state.rawValue, "MenuBarView", "struct MenuBarView", state.size.width, state.size.height) {
                await MenuBarMenuRendering.makeView(for: state)
            }
        }
        for variant in ["display", "window"] {
            add("recording-source-\(variant)", "RecordingSourceTargetPresenter", "private struct RecordingSourceTargetOverlay", 1000, 625) {
                AnyView(try StateRenderDesktop.view().overlay { RecordingSourceTargetPresenter.renderOverlay(window: variant == "window") })
            }
        }
        add("recording-camera-preview", "CameraRecordingManager", "static func renderPreview", 220, 220) {
            AnyView(StateRenderCameraPreview(player: AVPlayer(url: fixtures.project.cameraURL)).frame(width: 160, height: 160))
        }
        add("quick-look-screenshot", "QuickLookPreviewPresenter", "final class QuickLookPreviewPresenter", 900, 650) {
            AnyView(try StateRenderQuickLookPreview(url: fixtures.screenshots[0]))
        }
        add("quick-look-recording", "QuickLookPreviewPresenter", "final class QuickLookPreviewPresenter", 900, 650,
            windowTitle: fixtures.project.finalURL.lastPathComponent) {
            AnyView(StateRenderQuickLookMoviePreview(url: fixtures.project.screenURL))
        }
        for variant in ["pill", "notch", "notch-scrolled"] {
            add("teleprompter-\(variant)", "TeleprompterOverlayPresenter", "struct TeleprompterOverlayView", 620, 230) {
                let model = TeleprompterOverlayModel()
                model.isExpanded = true
                model.mode = variant.hasPrefix("notch") ? .notch(width: StateRenderDisplay.notchWidth ?? 180, height: StateRenderDisplay.menuBarHeight - 1) : .pill
                let script = variant == "notch-scrolled"
                    ? "Capture a clear view of the work. Annotate the important details. Share a result that the team can review. Record the walkthrough once, then trim the pauses. Export the final cut for the release notes."
                    : "Capture a clear view of the work. Annotate the important details. Share a result that the team can review."
                model.layout = TeleprompterScriptLayout(script: script, maximumLineWidth: model.textWidth, font: TeleprompterOverlayModel.measuringFont)
                model.spokenWordCount = variant == "notch-scrolled" ? 22 : 7
                return AnyView(TeleprompterOverlayView(model: model))
            }
        }
        for variant in ["selected", "dragging"] {
            add("recording-area-\(variant)", "RecordingAreaSelectionSheet", "final class RecordingAreaSelectionSheet", 1000, 625) {
                RecordingAreaSelectionPresenter.shared.installRenderSelection(active: true, selected: true, interacting: variant == "dragging")
                return try StateRenderDesktop.recordingAreaBackdrop()
            }
        }
        add("recording-area-dimming", "RecordingAreaHighlightPresenter", "final class RecordingAreaHighlightView", 1000, 625) {
            AnyView(try StateRenderDesktop.view().overlay {
                StateRenderAppKitView {
                    let view = RecordingAreaHighlightView()
                    view.highlightRect = StateRenderDesktop.recordingRect
                    return view
                }
            })
        }
        add("recording-live-pen", "RecordingPenPresenter", "final class RecordingPenView", 1000, 625) {
            RecordingPenStrokeStore.shared.clear()
            RecordingPenStrokeStore.shared.begin(at: CGPoint(x: 0.2, y: 0.3), lineWidth: 0.008)
            for point in [CGPoint(x: 0.4, y: 0.25), CGPoint(x: 0.6, y: 0.4), CGPoint(x: 0.8, y: 0.3)] { RecordingPenStrokeStore.shared.append(point) }
            RecordingPenStrokeStore.shared.end()
            return AnyView(try StateRenderDesktop.view().overlay { StateRenderAppKitView { RecordingPenView() } })
        }
        states.append(contentsOf: StateRenderAlertCatalog.states())
        return states
    }
}
