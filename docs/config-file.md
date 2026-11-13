---
review_status: unreviewed
approval_status: not_approved
---

# Configuration File

Upshot creates `~/.config/upshot/config.toml` at app launch when the file is absent. The file synchronizes preferences and shortcut assignments with the running app. A two-second timer checks file changes and saves changes made in Settings. App termination flushes pending Settings changes.

The file contains `[preferences]` and `[shortcuts]` tables. Upshot writes all supported preferences and every registered action. Missing entries preserve current values when importing a file. The first launch without a configuration file exports current preferences and shortcut assignments.

## Syntax

The supported TOML subset consists of these two tables, scalar decimal numbers, Boolean values, single-line double-quoted strings with JSON-compatible escapes, single-line literal strings, single-line arrays of strings or decimal numbers, bare keys, quoted keys, blank lines, and `#` comments outside strings. Use quoted keys for preference names containing periods and route names containing slashes. Inline tables, nested arrays, dates, multiline strings, numeric separators, and additional tables are rejected. Selection rectangles use four-number arrays; remembered display layouts use string arrays. Recording export defaults use a quoted JSON string.

```toml
[preferences]
autoSaveScreenshots = true
playSounds = false
captureDelaySeconds = 3
compressionQuality = 0.8
exportFormat = "png"
exportDirectoryPath = "~/Pictures/Upshot"
"afterCapture.screenshot.showOverlay" = true

[shortcuts]
"capture/fullscreen" = "option+18"
"capture/window" = "option+19"
"capture/area" = "option+20"
"capture/area-copy" = "control+option+8"
"capture/area-save" = "control+option+1"
"capture/area-upload" = "disabled"
"capture/self-timer" = "disabled"
"capture/previous-area" = "disabled"
```

Shortcut bindings contain `control`, `option`, `shift`, or `command`, separated by `+`, followed by the decimal macOS virtual key code. At least one modifier is required. Modifier names cannot repeat. Key codes range from 0 through 127. `disabled` removes the global shortcut. The shortcut recorder in Settings supplies bindings without requiring knowledge of key codes.

The five original defaults remain Option+1 through Option+5 for fullscreen, window, area, recording picker, and Capture Text. Additional actions start unassigned. Reset restores an action's default; Clear removes its binding. Search in either shortcut settings section searches every registered action. Show All Actions displays the entire catalog.

## Preferences

Supported Boolean keys:

- `autoSaveScreenshots`
- `saveButtonUsesConfiguredFolder`
- `autoCopyScreenshotsToClipboard`
- `autoCompressScreenshots`
- `playSounds`
- `showMenuBarIcon`
- `hideDockIcon`
- `includeAppWindowsInCaptures`
- `captureWindowShadow`
- `previewCloseAfterDragging`
- `lowResolutionEditorPreview`
- `trimFullscreenMenuBar`
- `recordingSystemAudio`
- `recordingTeleprompterEnabled`
- `revealExportInFinder`
- `agentServerEnabled`
- `libraryAnalyzeCaptures`
- `librarySortExistingCaptures`
- Applicable after-capture keys, using `afterCapture.<screenshot|recording>.<action>`. Screenshot actions are `showOverlay`, `upload`, `annotate`, and `pin`. Screenshot copy and save use `autoCopyScreenshotsToClipboard` and `autoSaveScreenshots`. Recording actions are `showOverlay`, `copy`, `save`, `upload`, and `openVideoEditor`.

Supported numeric keys:

- `compressionQuality`: 0.1–1.
- `captureDelaySeconds`: integer, 0–3600.
- `recordingStartDelaySeconds`: integer, 0–3600.
- `previewAutoCloseSeconds`: integer, 0–86400.
- `captureShelfHandlePosition`: 0–1.
- `recordingTeleprompterLineCount`: integer, 2–5.

Supported string keys:

- `exportFormat`: `png`, `jpeg`, or `heic`.
- `exportDirectoryPath`: export directory, with `~` expanded to the current home directory. Upshot writes home-relative export paths using `~`.
- `previewPosition`: `left` or `right`.
- `annotationStartingTool`: an existing annotation tool's raw value or `lastUsed`.
- `recordingCameraDeviceID`: camera device identifier; empty disables the camera.
- `recordingMicrophoneDeviceID`: microphone device identifier; empty disables the microphone.
- `recordingTeleprompterScript`: teleprompter script, with newlines escaped as `\n`.

Cloud credentials remain in their existing storage and are excluded from the configuration file. Complex editor documents, overlay layouts, capture history, and recording selection geometry retain their existing storage. Screenshot selection memory and recording delivery defaults also synchronize through the keys below.

## Import Behavior

Upshot validates the complete file before changing preferences. Unknown preference keys, unknown shortcut routes, invalid values, duplicate assignments, conflicting shortcuts, and shortcuts rejected by macOS prevent import. A failed import preserves the file and existing preferences. Shortcut registration failures restore the previous bindings.

Configuration errors produce `Configuration rejected error=<reason>`. Successful imports produce `Configuration loaded preferences and shortcuts`. Successful writes produce `Configuration saved preferences and shortcuts`. Successful shortcut updates produce `Shortcut updated action=<route> binding=<binding>` or `Shortcut catalog loaded bindings=<count>`.

Settings changes rewrite the file into the canonical format. This rewrite removes comments and preserves supported preference values and shortcut assignments. A file edit detected during the same synchronization cycle takes precedence over pending Settings changes. Invalid files remain untouched until corrected. Synchronization pauses while the shortcut recorder is active.

Upshot and Upshot Dev use the same configuration file. Concurrent instances observe each other's file changes. Each build retains its existing UserDefaults domain and agent socket.

## Verification

In an integration session, launch Upshot Dev and inspect the newly created configuration file. Change `playSounds` in the file and confirm Settings reflects the value after synchronization. Change the self-timer in Settings and confirm the file reflects the value. Assign a shortcut in Settings and confirm its route appears under `[shortcuts]`. Set two routes to the same shortcut and confirm import fails while the previous shortcuts remain available. Correct the conflict and confirm import succeeds. Close the app after changing a preference and verify the change persists in the file.

Settings → General → Configuration File provides Reveal Configuration, Reload Configuration, and configuration errors.

## Area Selection Preferences

- `areaSelectionFreezeScreen`: Boolean, default false.
- `areaSelectionCrosshair`: Boolean, default false.
- `areaSelectionMagnifier`: Boolean, default true.
- `allInOneLastMode`: string, default `area`; values `area`, `window`, `fullscreen`, `previousArea`, `element`, `scrolling`, and `recording`.
- `areaSelectionLastScreenshotRect`: empty array until a screenshot succeeds; otherwise `[x, y, width, height]` in global AppKit points. Width and height must each be at least one.
- `areaSelectionLastScreenshotDisplays`: string array, default empty; stores the participating display IDs and geometry.
- `allInOneLastSelectionRect`: empty array until selection; otherwise four numbers with the same coordinates and dimensions as the screenshot rectangle.
- `allInOneLastSelectionDisplays`: string array, default empty; stores display IDs and geometry independently of screenshot selection memory.

Remembered display geometry must match the attached displays before previous-area capture can reuse the rectangle.

## Screenshot Output Preferences

- `screenshotConvertToSRGB`: Boolean, default false.
- `screenshotScaleToOneX`: Boolean, default false.
- `screenshotBorder`: Boolean, default false.
- `screenshotRetinaSuffix`: Boolean, default false.
- `screenshotShowCursor`: Boolean, default false.
- `screenshotApplyBackgroundPreset`: Boolean, default false.
- `screenshotBackgroundPresetID`: string, default empty; empty selects the active annotation background preset, otherwise a saved preset UUID.
- `screenshotWindowBackground`: string, default `original`; values `original`, `wallpaper`, `customWallpaper`, and `transparent`.
- `screenshotWindowWallpaperPath`: string, default empty; the custom wallpaper image path. Home-relative paths expand on import and use `~` on export.
- `screenshotWindowPadding`: number from zero through 256 points, default 32; applies when window background differs from `original`.
- `screenshotHideDesktopIcons`: Boolean, default false.
- `screenshotFilenameTemplate`: string, default `Upshot_{date}-{time}`; tokens `{date}`, `{time}`, `{app}`, `{type}`, and `{counter}`. Empty templates and unsupported tokens reject import.
- `screenshotFilenameCounter`: nonnegative integer, default zero; increments once during filename generation for each processed screenshot.
- `screenshotAskForName`: Boolean, default false.
- `screenshotClipboardMode`: string, default `both`; values `file`, `image`, and `both`.

Shift at capture confirmation skips the automatic annotation background. With a self-timer, Shift is read at the shutter. Screenshot output changes run before history import, naming, automatic copying, saving, and sharing. Capture Text bypasses screenshot output processing.

## Recognition Preferences

- `recognitionDetectCodes`: Boolean, default false; automatically detect QR codes and barcodes after screenshot capture. Explicit code-detection commands remain available when automatic detection is disabled.
- `recognitionLanguage`: string, default empty for Automatic; available identifiers appear in Settings → Screenshots → Text Recognition.
- `recognitionKeepLineBreaks`: Boolean, default true.
- `recognitionDetectLinks`: Boolean, default true; controls link actions in recognition results while retaining payload copying.

## Annotation Preferences

Quote annotation preference names because they contain periods.

- `"annotationEditor.alwaysOnTop"`: Boolean, default false.
- `"annotationEditor.objectShadows"`: Boolean, default false; controls new objects and the existing selected-object action.
- `"annotationEditor.automaticallyExpandCanvas"`: Boolean, default false.
- `"annotationEditor.drawingSmoothing"`: number from zero through one, default 0.62; preserves the existing freehand stroke pipeline at its default.

## Quick Access Preferences

- `previewOverlaySize`: string, default `small`; values `small`, `medium`, and `large`.
- `previewAutoCloseAction`: string, default `close`; values `close`, `saveAndClose`, and `copyAndClose`.
- `previewCloseAfterUploading`: Boolean, default false.
- `previewSwipeTowardEdgeAction`: string, default `tuck`.
- `previewSwipeAwayFromEdgeAction`: string, default `none`.
- `pinnedScreenshotRoundedCorners`: Boolean, default true.
- `pinnedScreenshotShadow`: Boolean, default true.
- `pinnedScreenshotBorder`: Boolean, default true.

Both swipe keys accept `none`, `tuck`, `copy`, `save`, `annotate`, `pin`, `view`, `upload`, `compress`, `close`, and `delete`.

## History Preferences

- `historyRetentionDays`: nonnegative integer, default zero. Zero retains captures indefinitely. Positive values move older captures and recording projects to Trash. Captures in an open editor remain until a later cleanup.

## Recording Preferences

- `recordingDimOutsideArea`: Boolean, default false.
- `recordingDoNotDisturb`: Boolean, default false.
- `recordingFocusShortcutName`: string, default `Upshot Recording Focus`. The configured macOS Shortcut must implement snapshot, enable, and restore actions. The setting does not install that Shortcut.
- `recordingCapturesTypedKeys`: Boolean, default false; applies to future recordings. Command Keys Only remains the default export filter.
- `recordingExtendedExportDefaults`: quoted JSON string. Required fields are `format` (`Video` or `GIF`), `gifFrameRate` (10, 15, 20, 25, or 30), `gifQuality` (`Low`, `Medium`, or `High`), `optimizesGIF`, `scalesRetinaToOne`, `monoAudio`, and `separateAudioTracks`. Optional `motionBlurLevel` accepts `Off`, `Low`, `Medium`, or `High`. Invalid JSON and invalid enum values reject the whole configuration import.

Default recording delivery JSON:

```toml
[preferences]
recordingExtendedExportDefaults = '{"format":"Video","gifFrameRate":15,"gifQuality":"High","optimizesGIF":true,"scalesRetinaToOne":false,"monoAudio":false,"separateAudioTracks":false}'
```

Recording projects retain their own delivery and appearance files. The configuration key controls remembered delivery defaults rather than overwriting existing project settings.
