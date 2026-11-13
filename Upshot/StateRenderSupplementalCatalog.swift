import AppKit
import AVFoundation
import SwiftUI

struct StateRenderAlertView: NSViewRepresentable {
    let title: String
    let detail: String
    let buttons: [String]
    var field: String? = nil
    var critical = false

    func makeNSView(context: Context) -> NSView {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = critical ? .critical : .warning
        for title in buttons { alert.addButton(withTitle: title) }
        if let field {
            let text = NSTextField(string: field)
            text.frame = CGRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = text
        }
        alert.window.level = StateRenderer.renderLevel
        alert.window.isReleasedWhenClosed = false
        alert.layout()
        let content = alert.window.contentView!
        alert.window.contentView = nil
        alert.window.close()
        let container = NSView()
        container.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            content.widthAnchor.constraint(equalToConstant: content.frame.width),
            content.heightAnchor.constraint(equalToConstant: content.frame.height)
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum StateRenderSupplementalCatalog {
    static func states(fixtures: StateRenderFixtures) -> [StateRenderDefinition] {
        var states: [StateRenderDefinition] = []
        func add(_ name: String, _ source: String, _ marker: String, _ width: CGFloat, _ height: CGFloat,
                 _ view: @escaping () async throws -> AnyView) {
            states.append(StateRenderDefinition(name, source: source, marker: marker,
                                                 size: CGSize(width: width, height: height), makeView: view))
        }
        add("settings-general-permissions-denied", "SettingsGeneralPane", "struct GeneralSettingsPane", 1000, 820) {
            SettingsNavigation.shared.selectedTab = .general
            return AnyView(SettingsView())
        }
        for variant in ["configured", "connected", "failed"] {
            add("settings-cloud-\(variant)", "SettingsCloudPane", "struct CloudSettingsPane", 1000, 1000) {
                SettingsNavigation.shared.selectedTab = .cloud
                return AnyView(SettingsView())
            }
        }
        add("settings-mcp-disabled", "SettingsMCPPane", "struct MCPSettingsPane", 1000, 820) {
            UpshotStorage.defaults.set(false, forKey: UpshotPreferences.agentServerEnabledKey)
            SettingsNavigation.shared.selectedTab = .mcp
            return AnyView(SettingsView())
        }
        add("settings-section-after-recording-upload-paused", "AfterCaptureSettingsSection", "struct AfterCaptureActionsSection", 860, 520) {
            UpshotStorage.defaults.set(true, forKey: AfterCaptureAction.upload.storageKey(for: .recording))
            return AnyView(InterfaceFormPage { AfterCaptureActionsSection(type: .recording, title: "After Recording") })
        }
        add("design-gallery", "InterfaceStyleGallery", "struct InterfaceStyleGallery", 1380, 2900) {
            AnyView(InterfaceStyleGallery(backdrop: fixtures.image))
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
        for variant in ["camera", "cursor", "keystrokes", "look-expanded"] {
            add("studio-inspector-\(variant)", "RecordingStudioInspector", "struct StudioInspector", 420, 2400) {
                let model = try await fixtures.studioModel()
                return AnyView(StudioInspector(model: model).onDisappear { model.teardown() })
            }
        }
        add("annotation-load-failed", "AnnotationEditorWindow", "struct AnnotationLoadFailureView", 1280, 900) {
            let model = AnnotationEditorModel()
            model.errorMessage = "The screenshot could not be opened."
            return AnyView(AnnotationEditorWindow(url: .constant(fixtures.screenshots[0]), renderModel: model))
        }
        for variant in ["normal", "hover", "square"] {
            add("pinned-\(variant)", "PinnedScreenshotPresenter", "struct PinnedScreenshotView", 640, 400) {
                UpshotStorage.defaults.set(variant != "square", forKey: UpshotPreferences.pinnedScreenshotRoundedCornersKey)
                return AnyView(PinnedScreenshotView(image: fixtures.image, url: fixtures.screenshots[0], onClose: {}))
            }
        }
        for filter in ["capture-actions", "recording-controls", "history", "projects"] {
            add("menu-\(filter)", "MenuBarView", "struct MenuBarView", 500, filter == "capture-actions" ? 1600 : 900) {
                if filter == "history" { return AnyView(VStack(alignment: .leading, spacing: 10) { MenuBarView().renderHistoryMenu }.padding(18)) }
                if filter == "projects" { return AnyView(VStack(alignment: .leading, spacing: 10) { MenuBarView().renderProjectsMenu }.padding(18)) }
                let actions = CaptureHotkeyAction.allCases.filter {
                    filter == "capture-actions"
                        ? $0.route.hasPrefix("capture/") || [.toggleCrosshair, .toggleMagnifier, .toggleDesktopIcons].contains($0)
                        : $0.route.hasPrefix("recording/") && $0 != .screenRecording
                }
                return AnyView(VStack(alignment: .leading, spacing: 14) {
                    ForEach(actions) { action in Text(action.title).frame(maxWidth: .infinity, alignment: .leading) }
                }.padding(20))
            }
        }
        for variant in ["display", "window"] {
            add("recording-source-\(variant)", "RecordingSourceTargetPresenter", "private struct RecordingSourceTargetOverlay", 1000, 625) {
                AnyView(Image(nsImage: fixtures.image).resizable().overlay { RecordingSourceTargetPresenter.renderOverlay(window: variant == "window") })
            }
        }
        add("recording-camera-preview", "CameraRecordingManager", "static func renderPreview", 220, 220) {
            AnyView(StateRenderCameraPreview(player: AVPlayer(url: fixtures.project.cameraURL)).frame(width: 160, height: 160))
        }
        for variant in ["screenshot", "recording"] {
            add("quick-look-\(variant)", "QuickLookPreviewPresenter", "final class QuickLookPreviewPresenter", 900, 650) {
                AnyView(try StateRenderQuickLookPreview(url: variant == "screenshot" ? fixtures.screenshots[0] : fixtures.project.screenURL))
            }
        }
        for variant in ["pill", "notch"] {
            add("teleprompter-\(variant)", "TeleprompterOverlayPresenter", "struct TeleprompterOverlayView", 620, 230) {
                let model = TeleprompterOverlayModel()
                model.isExpanded = true
                model.mode = variant == "notch" ? .notch(width: 180, height: 32) : .pill
                model.layout = TeleprompterScriptLayout(script: "Capture a clear view of the work. Annotate the important details. Share a result that the team can review.", maximumLineWidth: model.textWidth, font: TeleprompterOverlayModel.measuringFont)
                model.spokenWordCount = 7
                return AnyView(TeleprompterOverlayView(model: model))
            }
        }
        for variant in ["selected", "dragging"] {
            add("recording-area-\(variant)", "RecordingAreaSelectionSheet", "final class RecordingAreaSelectionSheet", 1000, 625) {
                RecordingAreaSelectionPresenter.shared.installRenderSelection(active: true, selected: true, interacting: variant == "dragging")
                return AnyView(Image(nsImage: fixtures.image).resizable().overlay {
                    StateRenderAppKitView { RecordingAreaSelectionSheet(displayID: 0, screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 625), scale: 2) }
                })
            }
        }
        add("recording-area-dimming", "RecordingAreaHighlightPresenter", "final class RecordingAreaHighlightView", 1000, 625) {
            AnyView(Image(nsImage: fixtures.image).resizable().overlay {
                StateRenderAppKitView {
                    let view = RecordingAreaHighlightView()
                    view.highlightRect = CGRect(x: 180, y: 140, width: 640, height: 360)
                    return view
                }
            })
        }
        add("recording-live-pen", "RecordingPenPresenter", "final class RecordingPenView", 1000, 625) {
            RecordingPenStrokeStore.shared.clear()
            RecordingPenStrokeStore.shared.begin(at: CGPoint(x: 0.2, y: 0.3), lineWidth: 0.008)
            for point in [CGPoint(x: 0.4, y: 0.25), CGPoint(x: 0.6, y: 0.4), CGPoint(x: 0.8, y: 0.3)] { RecordingPenStrokeStore.shared.append(point) }
            RecordingPenStrokeStore.shared.end()
            return AnyView(Image(nsImage: fixtures.image).resizable().overlay { StateRenderAppKitView { RecordingPenView() } })
        }
        let alerts: [(String, String, String, String, [String], String?)] = [
            ("editor-unsaved", "EditorCloseGuard", "Do you want to save the changes to “Release Overview”?", "Your changes since the last save will be lost if you don't save them.", ["Save and Close", "Discard Changes", "Cancel"], nil),
            ("editor-unsaved-project", "EditorCloseGuard", "Do you want to save your project before closing or delete it?", "This recording has never been saved. Deleting it removes the footage as well.", ["Save and Close", "Delete and Close", "Cancel"], nil),
            ("library-rename", "CaptureLibraryView", "Rename Capture", "", ["Rename", "Cancel"], "Release Overview"),
            ("library-trash", "CaptureLibraryView", "Move capture to Trash?", "The local files and their edits will move to Trash. Exported copies and cloud links will remain available.", ["Move to Trash", "Cancel"], nil),
            ("library-trash-multiple", "CaptureLibraryView", "Move 3 captures to Trash?", "The local files and their edits will move to Trash. Exported copies and cloud links will remain available.", ["Move to Trash", "Cancel"], nil),
            ("library-error", "CaptureLibraryView", "The Library action could not be completed", "The capture could not be opened.", ["OK"], nil),
            ("cloud-delete", "CaptureLibraryInspector", "Delete from cloud?", "This permanently removes the cloud copy and breaks its share link. Your local capture stays in the Library.", ["Delete", "Cancel"], nil),
            ("annotation-delete-style", "AnnotationStyleStrip", "Delete Style?", "“Review” will be removed from your styles. This screenshot won’t change.", ["Delete", "Cancel"], nil),
            ("studio-delete-style", "RecordingStudioLook", "Delete Style?", "“Review” will be removed from your styles. This recording won’t change.", ["Delete", "Cancel"], nil),
            ("watermark-import-error", "AnnotationWatermarkSourceControls", "Watermark Image Failed", "The image could not be read.", ["OK"], nil),
            ("studio-media-import-error", "RecordingStudioTimelineDock", "Some files weren't added", "The selected media could not be read.", ["OK"], nil),
            ("capture-name", "ScreenshotCaptureNamePrompt", "Name Screenshot", "Enter the screenshot name. The PNG extension is added automatically.", ["Use Name", "Keep Generated Name"], "Release Overview"),
            ("recording-input-warning", "ScreenRecordingManager", "Some recording inputs are unavailable", "The selected microphone is no longer available, so it was turned off.", ["Continue"], nil),
            ("recording-ended-early", "ScreenRecordingManager", "The recording ended early, but your footage was saved", "The recording was interrupted.", ["OK"], nil),
            ("recording-save-error", "ScreenRecordingManager", "The recording could not be saved", "The recording destination could not be written.", ["OK"], nil),
            ("recording-start-error", "ScreenRecordingManager", "Couldn't start the recording", "The selected recording source is unavailable.", ["OK"], nil),
            ("recording-camera-export-error", "RecordingSessionRenderer", "The camera video could not be added", "Your screen, camera, and audio masters are safe in the recording project, but Upshot could not create the combined video: The export could not be completed.", ["OK"], nil),
            ("recording-recovered", "RecordingRecoveryCoordinator", "Recovered an interrupted recording", "The playable footage was preserved in History and can be reopened in Upshot Studio.", ["OK"], nil),
            ("screen-recording-permission", "ScreenRecordingManager", "Screen Recording permission needed", "Upshot can't record until it's allowed under Privacy & Security > Screen & System Audio Recording. After turning it on, quit and reopen Upshot - macOS applies the permission on relaunch.", ["Open System Settings", "Cancel"], nil),
            ("microphone-permission", "RecordingInputAuthorization", "Microphone access needed", "Allow Upshot to use the microphone in Privacy & Security, then select it again.", ["Open System Settings", "Cancel"], nil),
            ("camera-permission", "RecordingInputAuthorization", "Camera access needed", "Allow Upshot to use the camera in Privacy & Security, then select it again.", ["Open System Settings", "Cancel"], nil),
            ("automation-confirmation", "AutomationURLRouter", "Allow a link to run “Share”?", "Another app or a web page opened an Upshot link that uploads, shares, deletes, or saves changes.", ["Run", "Cancel"], nil),
            ("automation-error", "AutomationURLRouter", "Upshot could not perform the URL action", "Unknown Upshot route.", ["OK"], nil),
            ("screenshots-folder-error", "MenuBarView", "Could not open screenshots folder.", "The export folder is unavailable.", ["OK"], nil),
            ("quit-unsaved", "UpshotApp", "You have 1 unsaved capture", "These captures haven't been saved to your Mac and will be lost if you quit. Turn on Auto Save in Settings to keep every capture automatically.", ["Cancel", "Quit Anyway"], nil),
            ("quit-recording", "UpshotApp", "A screen recording is still in progress", "Upshot will finish and save the recording before quitting.", ["Cancel", "Finish Recording and Quit"], nil)
        ]
        for (name, source, title, detail, buttons, field) in alerts {
            add("alert-\(name)", source, source == "CaptureLibraryView" ? ".alert(" : "NSAlert()", 620, 400) {
                AnyView(StateRenderAlertView(title: title, detail: detail, buttons: buttons, field: field, critical: name == "recording-save-error"))
            }
        }
        return states
    }
}
