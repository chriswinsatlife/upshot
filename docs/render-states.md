---
review_status: agent_written
approval_status: not_approved
---

# Render States

## Command

Build the app, then run its executable in render mode:

```bash
xcodebuild build -project Upshot.xcodeproj -scheme "Upshot Dev" -configuration "Debug Dev" -destination "platform=macOS" -derivedDataPath .local/build
".local/build/Build/Products/Debug Dev/Upshot Dev.app/Contents/MacOS/Upshot Dev" --render-states .local/render-states
```

The regular Upshot executable accepts the same arguments. Render mode branches before SwiftUI app startup. It never starts the menu bar app, registers capture shortcuts, starts the updater, or starts a capture session.

A state name selects both appearances:

```bash
".local/build/Build/Products/Debug Dev/Upshot Dev.app/Contents/MacOS/Upshot Dev" --render-states .local/render-states --state annotation-tool-arrow
```

An appearance suffix selects one PNG:

```bash
".local/build/Build/Products/Debug Dev/Upshot Dev.app/Contents/MacOS/Upshot Dev" --render-states .local/render-states --state annotation-tool-arrow-dark
```

Unknown names and invalid arguments return a nonzero exit status. Each image uses the state name and an appearance suffix, such as `annotation-tool-arrow-light.png`. A state whose window content scrolls past the window produces one image per scroll position, named with a `-scroll-N` suffix, such as `settings-screenshots-expanded-scroll-2-light.png`. A frame name with or without the appearance suffix selects that single image.

## Display Frames

Every image is one display-sized frame of 1728 by 1117 points at two pixels per point (3456 by 2234 pixels). The main display must be at least that size at 2x; the renderer fails otherwise. The `selector-all-in-one-narrow` state uses an 800 by 600 point frame (1600 by 1200 pixels), because the All-In-One toolbar stacks its size fields only on a display narrower than `AllInOneCaptureToolbar.singleRowMinimumWidth` (820 points).

The wallpaper is the macOS Tahoe default, read from the Neptune One wallpaper extension because the Desktop Pictures folder does not contain the Tahoe images:

- Light: `/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources/TahoeLight.heic`
- Dark: `/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources/TahoeDark.heic`

The square image fills the display and is centered, as the desktop shows it. The menu bar strip is left clear; its 33-point height comes from the main display's visible frame.

`StateRenderStage` builds each frame from real windows: a borderless wallpaper window, then the state's windows above it. `StateRenderPlacement` assigns each state one placement:

- Settings, Library, Annotate, Studio, Quick Look, and the style gallery use titled windows with the product's style mask and toolbar style, centered with `NSWindow.center()`. Settings has a 700 by 540 content area; Library 1180 by 760; Annotate 1100 by 760; Studio 1360 by 860. These sizes exclude the toolbar, so Settings is 700 by 592 like its autosaved product frame.
- Floating UI uses a borderless panel at the frame its presenter computes. The presenters expose their frame math as static functions: `CaptureShelfPresenter.panelFrame`, `PinnedScreenshotPresenter.cascadedOrigin`, `CaptureHistoryPresenter.panelFrame`, `RecordingBarPresenter.panelFrame`, `CaptureCountdownPresenter.centeredOrigin`, `CaptureTextFeedbackPresenter.origin`, `CaptureCodeFeedbackPresenter.origin`, `TeleprompterOverlayPresenter.panelFrame`, `CameraRecordingManager.previewFrame`, and `ScrollingCaptureControlPanel.panelFrame`. Scrolling capture controls surround a Library window, and recording bar area states sit over the recording area sheet.
- Selector, recording source, recording area, and live pen states cover the display. Their frozen screen image is the Tahoe wallpaper with the fixture window centered on it at whole-point coordinates, scaled down only when the display is narrower than the window plus 64-point margins. `StateRenderDesktop.selectorHighlight` gives the selection each selector mode draws: the fixture window frame for Window and the armed Timer, the fixture window's Recordings card for Element, the whole display for Fullscreen, and for the Capture Area drag a whole-point rectangle with the pointer at its lower-right corner. `AreaSelectionMagnifier.placement` rejects a panel whose rounded frame overlaps the selection, so selections use whole points.
- Alerts use the alert content from `NSAlert` in a window with the alert's glass frame style, positioned near the top of the Library, Annotate, or Studio window they belong to (the never-saved recording alert belongs to the Studio window), or centered on the display when they belong to no window. AppKit keeps the real `_NSAlertPanel` off the window server outside a modal session, so the renderer removes those two modal style bits.
- Popover content appears in an `NSGlassEffectView` panel beside the button that opens it in the Annotate or Studio window. The renderer never shows `NSPopover`, because AppKit can move a popover window onto the display before its level can be lowered.
- Menu bar menu states draw the menu replica on the `.menu` visual effect material below the menu bar area.

Titled windows report key and main appearance to AppKit, so they draw colored window controls and active sidebars without becoming key. The window server draws no shadow for windows below the desktop level, so `StateRenderShadow` draws each shadow from the window's own shape and the active shadow parameters AppKit assigns to it (density 0.4, radius 20, vertical offset 18, and rim 0.6 at radius 3 for titled windows), in a window directly beneath it.

ScreenCaptureKit captures the frame with `SCScreenshotManager.captureImage` and a display filter that includes only the stage's windows, so window-server materials, Liquid Glass, and vibrancy sample the wallpaper and windows behind them. Before capture, the renderer requires every included window to be ordered in and below the desktop layer according to `SCShareableContent`.

## Output

- `catalog.json` lists the selected states, source locations, render status, and frame names.
- `manifest.json` records each image’s name, base state, appearance, scroll frame number, production source file, source line, pixel dimensions, scale, capture method, highest window-server layer, desktop layer, wallpaper path, and filename.
- `contact_sheet.png` contains every rendered image with its name below its thumbnail.
- `isolation-before.json` and `isolation-after.json` record protected paths, modification times, and regular file sizes. Paths under the home directory use a tilde.
- Standard error records each rendered state with its frame count and duration.

The renderer uses activation policy `prohibited`. Render windows cannot become key or main windows, ignore mouse events, and stay below the desktop window level, so the display never shows them. The renderer verifies its activation policy, inactive state, and every window's level before and after each capture.

Rendering requires existing Screen Recording access for the rendering app. The renderer never requests it and fails when it is missing.

The isolation check compares the installed Upshot app's real data, so a full-catalog run fails when that app captures, indexes its Library, or rewrites its configuration during the run. Rendering each state with `--state` in its own process shortens each check to a few seconds; a state whose check fails can be rendered again.

## Fixture Isolation

`UpshotStorage` routes direct defaults access to a unique render suite. The SwiftUI root supplies the same suite through `defaultAppStorage`. History, recording projects, wallpapers, the Library index, exports, the agent socket path, and the configuration path resolve inside a temporary fixture directory. Normal launches retain their existing storage locations.

The fixture generator creates screenshots, a GIF, screen and camera movies, narration audio, a recording manifest, pointer events, and recording project metadata. Production views receive those files and deterministic view state. Rendering disables hardware device discovery, live source discovery, OCR work, cloud connection requests, Keychain access, and updater construction. Overlay presenters are never called to display overlays; their views render inside the renderer’s windows.

The renderer compares the real Application Support tree, configuration directory, and regular and Dev defaults files before and after rendering. An observed modification changes the run to a failure. Successful runs remove the fixture directory and render defaults domain before exiting.

## Coverage

- Settings: General, Screenshots, Screen Recordings, Overlay, MCP, Cloud, and About; expanded panes; all keyboard shortcuts; each composed settings section; missing permissions; disabled MCP; configured, connected, and failed Cloud states.
- Library: grid, list, empty, search results, empty search results, screenshot and recording filters, selected capture inspector, and multiple selection inspector.
- Annotation editor: every annotation tool, generated annotations, clean image, crop, background inspector, border, camera, progressive blur, color adjustments, watermark, background picker, load failure, and New Style popover.
- Studio: Look, selected zoom, selected layout, selected text, selected redaction, selected image, selected audio, Captions, transcript editing, crop, export progress, export failure, and share failure; one page per tool rail button (Camera, Zoom, Cursor, Keystrokes, Audio, Clip); video and GIF export options; audio export options; New Style and Share Options popovers.
- Quick Access: one card, several cards, hover actions, tucked handle, image and video cards, compression and preparation activity, copied link, failed upload, compressed result, and failed action.
- Pinned screenshots: default, hover toolbar, square corners, and no border, all showing the full fixture screenshot in both appearances. The Border preference draws a 1-point stroke, so the no-border state differs from the default by that line only.
- Capture History: every filter and the empty strip.
- Screenshot selection: area, window, element, crosshair with magnifier, and every All-In-One mode, drawn over a generated image.
- Scrolling capture: manual ready, automatic ready, running, and finishing controls.
- Recording: picker, teleprompter editor, visible-window reminder, selected area, recording, paused, starting, finishing, each countdown value, area selection and dragging, outside-area dimming, live pen, notch and pill teleprompters, display and window source targeting, and camera preview.
- Feedback: copied text, no text, failed text recognition, QR codes, barcodes, links, and combined codes and links.
- Menu bar: main menu content, capture actions, recording controls, recent captures, and recording projects.
- App alerts: editor save decisions, Library rename and deletion, cloud deletion, style deletion, watermark import failure, media import failure, capture naming, recording input warnings, recording failures, recording recovery, permission explanations, automation confirmation and failure, screenshots folder failure, and quit decisions.

The Quick Look screenshot preview shows a generated fixture file in an embedded Quick Look view. The embedded Quick Look view draws a movie in an out-of-process `NSRemoteView` whose playback controls appear only under the pointer, so the Quick Look recording preview shows the fixture movie in an `AVPlayerView` with floating controls, paused at the start, in a window titled with the recording's deliverable file name (`RecordingSession.finalURL`). The native Quick Look panel, macOS file and color chooser panels, and Sparkle update windows remain outside the catalog. These system and updater presentations do not have fixture-safe adapters in the renderer.

## Add a State

Add a `StateRenderDefinition` in `StateRenderCatalog` or `StateRenderSupplementalCatalog`. Use a unique filename-safe base name, the production source filename, a source marker, a layout size in points, and a factory returning the production view. The factory may load generated fixture media asynchronously. An optional scroll fraction captures one lower portion of a scroll view. `StateRenderPlacement.resolve` assigns the window, panel, display, alert, or popover placement from the state name; add a case there when a new state needs a placement other than a centered panel. Settings states and `annotation-background` produce one frame per scroll position.

Use fixture models and the existing render-only construction methods. For a new overlay, expose its view separately from the presenter. The factory must not call a presenter that opens windows, captures pixels, activates the app, reads production data, or starts hardware services. Render-only methods must assert `UpshotStorage.isRenderingStates`.

Regenerate the embedded source locations after editing production source files:

```bash
node scripts/update-render-state-sources.mjs
```

The embedded locations let an installed app write source references without reading a source checkout. Rebuild, run the selected state, and inspect both PNGs at full size. Check the manifest dimensions, capture method, and below-desktop level. Run the complete catalog after changes that affect fixture construction, shared storage, appearance, or capture.
