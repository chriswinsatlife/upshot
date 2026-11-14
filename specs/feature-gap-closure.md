---
review_status: unreviewed
approval_status: not_approved
gap_source: docs/feature-gaps.md
---

# Feature Gap Closure

## Scope

Every gap in `docs/feature-gaps.md` is in scope except the cloud items: S3, R2, and Google Drive upload, link expiry, the R2 share viewer, and a hosted cloud account. "Close after uploading" stays in scope because it is a Quick Access setting on the existing Cloudflare Worker upload.

## Working Copies

Agents never share one checkout, because a half-finished edit by one agent breaks every other agent's build. Each workstream gets its own `git clone` of `main` in `.local/workstreams/<workstream>/`, which is gitignored. Each agent commits atomic changes on `main` inside its clone, builds with its own `-derivedDataPath`, and never pushes. The integrating agent fetches each clone into `~/github/upshot`, rebases the commits onto `main`, builds, and pushes.

## Shared Files

Agents add new files wherever possible; the project uses synchronized folder groups, so a new file in `Upshot/` builds without a project file edit. Three rules keep edits to shared files small:

- Preference keys go in a new file per workstream as an `extension UpshotPreferences`, never in `UpshotPreferences.swift`.
- Settings UI goes in a new section view per workstream. The integration phase places each section into a settings pane.
- New capture actions are exposed as `static` entry points. Workstream I alone edits `CaptureHotkeys.swift`, `HotkeyManager.swift`, `MenuBarView.swift`, and `UpshotApp.swift`, and wires every action in phase two.

## Phase One

All workstreams run at the same time, one agent each, on `gpt-6.1-sol` with high reasoning through Codex.

Status: done.

- A, Area Selection. Owns `ScreenshotManager.swift`, `CaptureCoordinator.swift`, and `TextCaptureSelection.swift`, which it generalizes into the area selector for every area capture. Status: done.
  - Own selector with frozen screen, crosshair and magnifier. Status: done. Implementing file: `Upshot/AreaCaptureSelection.swift`.
  - Capture previous area for screenshots. Status: done. Implementing file: `Upshot/ScreenshotManager.swift`.
  - Selection spanning several displays. Status: done. Implementing file: `Upshot/AreaCaptureSelection.swift`.
  - Smart element capture through Accessibility. Status: done. Implementing file: `Upshot/AreaSelectionAccessibility.swift`.
  - All-In-One capture mode. Status: done. Implementing file: `Upshot/AllInOneCaptureMode.swift`.
- B, Screenshot Output. Owns `ScreenshotFileNaming.swift` and new post-processing files. Status: done.
  - sRGB conversion. Status: done. Implementing file: `Upshot/ScreenshotPixelProcessor.swift`.
  - Retina 1x scaling. Status: done. Implementing file: `Upshot/ScreenshotPixelProcessor.swift`.
  - 1px border. Status: done. Implementing file: `Upshot/ScreenshotPixelProcessor.swift`.
  - @2x suffix. Status: done. Implementing file: `Upshot/ScreenshotFileNaming.swift`.
  - Cursor on screenshots. Status: done. Implementing file: `Upshot/ScreenshotCursorService.swift`.
  - Background preset on every screenshot with Shift to skip. Status: done. Implementing file: `Upshot/ScreenshotBackgroundService.swift`.
  - Wallpaper or transparent window background with padding. Status: done. Implementing file: `Upshot/ScreenshotWindowBackground.swift`.
  - Hide desktop icons while capturing. Status: done. Implementing file: `Upshot/DesktopIconVisibilityService.swift`.
  - Filename templates. Status: done. Implementing file: `Upshot/ScreenshotFileNaming.swift`.
  - Ask for name after capture. Status: done. Implementing file: `Upshot/ScreenshotCaptureNamePrompt.swift`.
  - Clipboard mode. Status: done. Implementing file: `Upshot/ScreenshotClipboardService.swift`.
- C, Text Recognition. Owns `ImageTextRecognizer.swift` and every OCR caller's error path. Status: done.
  - QR and barcode detection with link prompts. Status: done. Implementing files: `Upshot/CaptureCodeRecognizer.swift`, `Upshot/CaptureCodeFeedbackPresenter.swift`.
  - Contrast and vertical CJK retry passes. Status: done. Implementing file: `Upshot/ImageTextRecognizer.swift`.
  - VisionKit Live Text before Vision. Status: done. Implementing file: `Upshot/ImageTextRecognizer.swift`.
  - Recognition language. Status: done. Implementing files: `Upshot/TextRecognitionPreferences.swift`, `Upshot/ImageTextRecognizer.swift`.
  - Keep line breaks. Status: done. Implementing files: `Upshot/TextRecognitionPreferences.swift`, `Upshot/ImageTextRecognizer.swift`.
  - Detect links. Status: done. Implementing file: `Upshot/CaptureCodeRecognizer.swift`.
  - Distinct capture and recognition errors in every caller. Status: done. Implementing files: `Upshot/ImageTextRecognizer.swift`, `Upshot/CaptureCoordinator.swift`, `Upshot/CaptureTextActions.swift`, `Upshot/CaptureCodeActions.swift`, `Upshot/SmartRedactionRecognizer.swift`, `Upshot/AnnotationEditorModel.swift`.
- D, Annotation Editor. Owns `Annotation*.swift` and `Engine/`. Status: done.
  - Callout and label text styles. Status: done. Implementing file: `Upshot/AnnotationTextDecoration.swift`.
  - Highlighter with text snapping. Status: done. Implementing files: `Upshot/Engine/AnnoHighlighter.swift`, `Upshot/AnnotationTextBoxRecognizer.swift`.
  - Measure tool. Status: done. Implementing file: `Upshot/AnnotationMeasurement.swift`.
  - Watermark. Status: done. Implementing file: `Upshot/AnnotationBackgroundPreviewViews.swift`.
  - Combine images. Status: done. Implementing files: `Upshot/AnnotationEditorImageCombination.swift`, `Upshot/AnnotationImageCombination.swift`.
  - Additional blur styles. Status: done. Implementing files: `Upshot/Engine/Shape.swift`, `Upshot/AnnotationRedactionFilters.swift`.
  - Color grading. Status: done. Implementing file: `Upshot/AnnotationColorAdjustments.swift`.
  - Rotate. Status: done. Implementing file: `Upshot/AnnotationImageTransform.swift`.
  - Flip. Status: done. Implementing file: `Upshot/AnnotationImageTransform.swift`.
  - Inverse arrow with Option. Status: done. Implementing files: `Upshot/SettingsAnnotatePreferences.swift`, `Upshot/Engine/AnnoEditorInteraction.swift`.
  - Smooth drawing. Status: done. Implementing file: `Upshot/AnnotationEditorPreferences.swift`.
  - Object shadows. Status: done. Implementing file: `Upshot/Engine/AnnoShapeDrawing.swift`.
  - Automatically expanding canvas. Status: done. Implementing file: `Upshot/AnnotationCanvasExpansion.swift`.
  - Always on top. Status: done. Implementing file: `Upshot/AnnotationEditorWindowLevel.swift`.
  - Color names. Status: done. Implementing file: `Upshot/AnnotationInspectorStyleMenus.swift`.
- E, Quick Access and Pins. Owns `CaptureShelf*.swift` and `PinnedScreenshotPresenter.swift`. Status: done.
  - Overlay size. Status: done. Implementing file: `Upshot/CaptureShelfPresenter.swift`.
  - Auto-close action. Status: done. Implementing file: `Upshot/CaptureShelf.swift`.
  - Option-drag to keep. Status: done. Implementing file: `Upshot/CaptureShelf.swift`.
  - Keeping the card on a cancelled drag. Status: done. Implementing file: `Upshot/CaptureShelf.swift`.
  - Close after uploading. Status: done. Implementing file: `Upshot/CaptureShelf.swift`.
  - Hover single-key shortcuts. Status: done. Implementing file: `Upshot/CaptureShelfKeyboardShortcuts.swift`.
  - Swipe actions. Status: done. Implementing file: `Upshot/CaptureShelfPresenter.swift`.
  - Pinned screenshot corners, shadow, and border. Status: done. Implementing file: `Upshot/PinnedScreenshotPresenter.swift`.
- F, Capture History. Owns `ScreenshotHistoryStore.swift` and new history strip files. Status: done.
  - Full-width recent captures strip with All, Screenshots, Videos, GIFs, and Video Projects filters and Restore. Status: done. Implementing files: `Upshot/CaptureHistoryPresenter.swift`, `Upshot/CaptureHistoryView.swift`, `Upshot/CaptureHistoryModel.swift`.
  - Restore last capture. Status: done. Implementing file: `Upshot/CaptureHistoryModel.swift`.
  - History retention. Status: done. Implementing file: `Upshot/CaptureHistoryRetention.swift`.
- G, Recording Export. Owns `RecordingExport*.swift`, `RecordingStudioExporter.swift`, and `RecordingStudio*Inspector.swift`. Status: done.
  - GIF export with frame rate, resolution, and quality. Status: done. Implementing files: `Upshot/RecordingExportGIF.swift`, `Upshot/RecordingExportOptions.swift`.
  - Retina 1x video. Status: done. Implementing file: `Upshot/RecordingStudioExporter.swift`.
  - Mono audio. Status: done. Implementing file: `Upshot/RecordingAudioChannels.swift`.
  - Separate audio tracks. Status: done. Implementing file: `Upshot/RecordingAudioTrackExport.swift`.
  - Motion blur levels. Status: done. Implementing file: `Upshot/RecordingExportPreferences.swift`.
  - Smooth and Dynamic zoom styles. Status: done. Implementing file: `Upshot/RecordingExportAppearance.swift`.
  - Keystroke size, style, nine positions, and key filter. Status: done. Implementing file: `Upshot/RecordingExportKeystrokes.swift`.
  - 3D shots. Status: done. Implementing file: `Upshot/RecordingExportShot.swift`.
  - Aspect reframing. Status: done. Implementing file: `Upshot/RecordingExportReframe.swift`.
- H, Live Recording. Owns `RecordingBar*.swift`, `RecordingControlPresenter.swift`, and `ScreenRecordingManager.swift`. Status: done.
  - Recording time in the menu bar. Status: done. Implementing file: `Upshot/RecordingMenuBarLabel.swift`.
  - Dim screen while recording. Status: done. Implementing file: `Upshot/RecordingAreaHighlightPresenter.swift`.
  - Do Not Disturb while recording. Status: done. Implementing file: `Upshot/RecordingFocusController.swift`.
  - Live pen annotation during recording. Status: done. Implementing file: `Upshot/RecordingPenPresenter.swift`.
- I, Automation. Owns the hotkey, menu, and app entry files. Delivers in phase one. Status: done.
  - URL scheme. Status: done. Implementing file: `Upshot/AutomationURLRouter.swift`.
  - `upshot` capture CLI over the existing socket. Status: done. Implementing file: `Upshot/AutomationCommandLine.swift`.
  - Searchable shortcut catalog. Status: done. Implementing file: `Upshot/SettingsShortcutsPane.swift`.
  - Configuration file, `~/.config/upshot/config.toml`. Status: done. Implementing file: `Upshot/AutomationConfiguration.swift`.

## Phase Two

Status: open.

Gated on phase one. Runs one agent at a time on `~/github/upshot` itself.

- Scrolling capture, built on workstream A's selector. Status: done. Implementing file: `Upshot/ScrollingCaptureSession.swift`.
- Workstream I wires every new action into shortcuts, the menu, the URL scheme, and the CLI. Status: open. Shortcuts (`Upshot/SettingsShortcutsPane.swift`), the URL scheme (`Upshot/AutomationURLRouter.swift`), and the CLI (`Upshot/AutomationCommandLine.swift`) are wired for all 83 `CaptureHotkeyAction` cases. The menu is not. `Upshot/MenuBarView.swift` lists 12 actions in `menuActions`, and it has no entry for Capture Previous Area, Capture Smart Element, Toggle Selection Crosshair, Toggle Selection Magnifier, Toggle Desktop Icons, Open Capture History, Restore Last Capture, Toggle Recording Live Pen, Clear Recording Live Pen, or any editor or recording editor action.
- The integrating agent places every settings section into its pane and rebuilds. Status: open. `QuickAccessSettingsSection` (`Upshot/QuickAccessSettingsSection.swift`) is not placed in a pane. Its only reference is in `OverlaySettingsPane` (`Upshot/SettingsPlaceholderPanes.swift`), which no view instantiates. `SettingsQuickAccessPane` (`Upshot/SettingsQuickAccessPane.swift`) implements the same controls inline. `CaptureHotkeySettingsSection` (`Upshot/CaptureHotkeySettingsSection.swift`) is not instantiated anywhere.

## Verification

Build success proves nothing. Each feature needs one of these as evidence:

- Window captures with `screencapture -l` of the Upshot Settings, Library, editor, and Studio windows, which do not take over the display.
- Exported files, such as a GIF from a Studio project exported through the MCP tools, inspected frame by frame.
- Log lines from the running Upshot app. The human user is never asked to use the Upshot Dev build.
- For features that cover the whole screen, such as the area selector, the history strip, and dim screen, a test session run by the user, with the agent reading the logs afterwards.

Each workstream's final diff and evidence go to an independent review by `gpt-6-luna` before integration. The integrating agent rejects findings that expand scope.
