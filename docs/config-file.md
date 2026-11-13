---
review_status: unreviewed
approval_status: not_approved
---

# Configuration File

Upshot creates `~/.config/upshot/config.toml` at app launch when the file is absent. The file synchronizes preferences and shortcut assignments with the running app. A two-second timer checks file changes and saves changes made in Settings. App termination flushes pending Settings changes.

The file contains `[preferences]` and `[shortcuts]` tables. Upshot writes all supported scalar preferences and every registered action. Missing entries preserve current values when importing a file. The first launch without a configuration file exports current preferences and shortcut assignments.

## Syntax

The supported TOML subset consists of these two tables, scalar decimal numbers, Boolean values, single-line double-quoted strings with JSON-compatible escapes, single-line literal strings, bare keys, quoted keys, blank lines, and `#` comments outside strings. Use quoted keys for preference names containing periods and route names containing slashes. Arrays, inline tables, dates, multiline strings, numeric separators, and additional tables are rejected.

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

Cloud credentials remain in their existing storage and are excluded from the configuration file. Complex editor documents, overlay layouts, capture history, and recording selection geometry retain their existing storage.

## Import Behavior

Upshot validates the complete file before changing preferences. Unknown preference keys, unknown shortcut routes, invalid values, duplicate assignments, conflicting shortcuts, and shortcuts rejected by macOS prevent import. A failed import preserves the file and existing preferences. Shortcut registration failures restore the previous bindings.

Configuration errors produce `Configuration rejected error=<reason>`. Successful imports produce `Configuration loaded preferences and shortcuts`. Successful writes produce `Configuration saved preferences and shortcuts`. Successful shortcut updates produce `Shortcut updated action=<route> binding=<binding>` or `Shortcut catalog loaded bindings=<count>`.

Settings changes rewrite the file into the canonical format. This rewrite removes comments and preserves supported preference values and shortcut assignments. A file edit detected during the same synchronization cycle takes precedence over pending Settings changes. Invalid files remain untouched until corrected. Synchronization pauses while the shortcut recorder is active.

Upshot and Upshot Dev use the same configuration file. Concurrent instances observe each other's file changes. Each build retains its existing UserDefaults domain and agent socket.

## Verification

In an integration session, launch Upshot Dev and inspect the newly created configuration file. Change `playSounds` in the file and confirm Settings reflects the value after synchronization. Change the self-timer in Settings and confirm the file reflects the value. Assign a shortcut in Settings and confirm its route appears under `[shortcuts]`. Set two routes to the same shortcut and confirm import fails while the previous shortcuts remain available. Correct the conflict and confirm import succeeds. Close the app after changing a preference and verify the change persists in the file.

Add `AutomationSettingsSection()` to the General settings page during integration to expose Reveal Configuration, Reload Configuration, and configuration errors.
