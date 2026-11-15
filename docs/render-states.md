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

## Live State

Live mode builds a state and keeps it open and running instead of capturing it once and exiting. One process can present one state after another:

```bash
".local/build/Build/Products/Debug Dev/Upshot Dev.app/Contents/MacOS/Upshot Dev" --present-live-state settings-advanced-light
```

Live mode is the shared UyuniLiveState package, which implements the app side of the live state contract in Uyuni's `specs/native_app_frames.md`. `Packages/UyuniLiveState` is an unmodified copy of `packages/uyuni_live_state_swift` from the Uyuni repository, with the source commit in `Packages/UyuniLiveState/provenance.yaml`; `scripts/update-uyuni-live-state-package.sh [UYUNI_COMMIT]` replaces the copy and rewrites that file. `Packages/UyuniLiveState/README.md` describes the package's launch arguments, output and input lines, window level guards, display safety check, input replay, alerts, menus, interaction guards, and standard error events. Upshot supplies `UpshotLiveStates` in `StateRenderLivePresentation.swift`, and `StateRenderer.run()` hands a `--present-live-state` or `--list-live-states` launch to `LiveStateRuntime.run` before render mode starts.

The name is a frame name with an appearance suffix, such as `settings-advanced-light`. A state with several scroll positions opens at its top. Every state that render mode renders can be presented, and the listing names each catalog state once per appearance with an empty `unsupported` list. `UpshotLiveStates` uses the same fixture isolation, catalog definition, placement, fixtures, and window construction as render mode, and draws no window shadows:

- A state placed in one titled window (Settings, Library, Annotate, Studio, Quick Look, and the style gallery) is presented as that window.
- An alert state builds its context window, if any, on the render stage and hands the `NSAlert` to `LiveStatePresentation(alert:over:)`, which moves the alert into a window 24 points below the context window's title bar, or centered with `NSWindow.center()` when it has no context window. The package then blocks pointer input to the windows behind the alert, sends keys to the alert, and makes each alert button remove the alert, as its README describes. The product action that would follow the answer, such as moving a capture to the Trash, does not run.
- Every other state, such as a popover panel beside a window, a borderless panel such as Quick Access, an overlay that covers the display such as a selector, or a menu bar menu replica, is presented as a region of the stage's windows with the wallpaper window as the package's backdrop window.

The region of an alert or region state is the smallest rectangle that holds the state's own windows, widened by `StateRenderLivePresentation.regionMargin` (40 points) on every side and clipped to the display frame render mode captures for that state. A titled window, an alert window, or an opaque window counts with its frame. A transparent borderless panel, such as the full-height Quick Access panel or a menu replica with its shadow room, counts with the bounds of its drawn pixels: one `SCScreenshotManager` capture of that window alone, at two pixels per point without its shadow, gives the rectangle of pixels with alpha above 8, and a `region_window_drawn_frame` event on standard error records the window frame and the drawn frame when they differ. Without Screen Recording access, or when the capture fails, the panel counts with its frame. A state whose window covers the display, such as a selector, a recording area, or the live pen, therefore keeps the whole display. `windowWidth` and `windowHeight` in `live_state_ready` give the region's size, such as 340 by 328 points for `alert-capture-name-light` and 1728 by 1117 for a selector.

A menu that a control in a state opens, such as a SwiftUI `Picker` in menu style, a SwiftUI `Menu`, or a context menu, is drawn by the package inside the window that opened it and takes clicks, keys, and `mouse_moved` highlighting there; AppKit menu tracking never runs. A menu bar menu state is a below-desktop replica that render mode builds, and the real `NSPopover` is never shown.

Building a state resets the render defaults suite and sets shared render state, so `UpshotLiveStates.sharedStateRestoration()` records the suite's persistent domain, the `SettingsNavigation` tab, search text, and detail, the app appearance, `StateRenderDisplay.size`, `StateRenderDesktop.image`, and `StateRenderer.scenario` before each `present` and restores them when it fails. Shared models that a state's factory configures directly, such as `AreaCaptureSelection.shared` or `CaptureShelf.shared`, are not recorded. Each `present` starts from the state's fixture defaults, so changes made through input do not carry over. `endFixtureIsolation()` removes the render defaults domain and the fixture directory and writes an `isolation_compared` event with the protected paths that changed during the run.

Upshot adds three behaviors to the package's input handling through its own window classes, without changing the package copy:

- `StateRenderTitledWindow` and `StateRenderWindow` offer a key down without the command or control modifier to `performKeyEquivalent(with:)` before handling it, the order in which `NSApplication` offers every key down, so Escape and Return reach a SwiftUI button's `keyboardShortcut(.cancelAction)` or `keyboardShortcut(.defaultAction)`.
- Live mode has no main menu, so Command-A, Command-C, Command-V, and Command-X with no other modifier, when no key equivalent takes them, send `selectAll:`, `copy:`, `paste:`, or `cut:` up the responder chain from the window's first responder with `tryToPerform(_:with:)`, write an `edit_command_performed` event, and use the general pasteboard as the product does. The two window classes do this in `performKeyEquivalent(with:)`, and an alert window does it through a `StateRenderEditCommandView` added to its content view.
- Each `makeLiveStatePresentation(for:)` writes `{"event":"present_started","state":NAME,"time":TIME}` with an ISO 8601 time in UTC to the millisecond. A process exit through `exit` writes a `process_exit` event, and `SIGTERM`, `SIGHUP`, or `SIGINT` writes a `process_signal` event before the signal ends the process with its default action. A process that ends with neither line after its last `present_started` ended through `SIGKILL` or another signal that cannot be caught.

The package gives each stage window the collection behaviors `canJoinAllSpaces`, `stationary`, and `ignoresCycle`. On 2026-11-14 three Settings states failed with "was not ordered in at the window server" while Mission Control, opened from a hot corner, showed for about 6 seconds; AppKit documents a `stationary` window as unaffected by Mission Control.

A product action in a state can open an alert sheet, a window sheet, or a modal alert, such as the Library's "Move Capture to Trash?" confirmation, or a new product window, such as the `RecordingBarPanel` that Record Screen in the Library's New Capture menu creates. The package shows sheets and modal alerts inside the presenting window, blocks `makeKeyWindow` and app activation, and keeps every new window below the desktop level, as its README describes. A confirmed action runs as in the product, with two differences while `UpshotStorage.fixtureRoot` is set. `UpshotStorage.trashItem(at:)` moves the files of a capture that the Library moves to the Trash into `Trash` inside the fixture directory, which is removed when the run ends, and never into the macOS Trash. A Library state's fixture gives its captures sources (Safari, Preview, Notes), a shared link, and edit marks that the fixture history does not store, so `CaptureLibraryModel.installRenderItems` keeps those values by capture ID and `refresh()` applies them to the rescanned captures with the same ID; a reload after Move to Trash, a rename, an export, or a new capture keeps the Apps section and each remaining capture as the state showed them.

The presentable frame names come from the same catalog:

```bash
".local/build/Build/Products/Debug Dev/Upshot Dev.app/Contents/MacOS/Upshot Dev" --list-live-states
```

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

`UpshotStorage` routes direct defaults access to a unique render suite. The suite name, `UpshotStorage.defaultsSuiteName`, is the absolute path of a plist inside the fixture directory, so the preferences system keeps the suite there instead of in `~/Library/Preferences`. A suite named by a domain identifier left an empty 42-byte `~/Library/Preferences/co.chrisyork.upshot.render-states.<UUID>.plist`, which `cfprefsd` wrote a few seconds after the process exited even though the process had removed the domain; the path-named suite leaves no file in either folder after exit. The SwiftUI root supplies the same suite through `defaultAppStorage`. History, recording projects, wallpapers, the Library index, exports, the agent socket path, and the configuration path resolve inside a temporary fixture directory. Normal launches retain their existing storage locations.

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
