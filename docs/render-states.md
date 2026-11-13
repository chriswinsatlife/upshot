---
review_status: unreviewed
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

Unknown names and invalid arguments return a nonzero exit status. Each image uses the state name and an appearance suffix, such as `annotation-tool-arrow-light.png`. Each image contains two pixels per layout point.

## Output

- `catalog.json` lists the selected states, source locations, and render status.
- `manifest.json` records each image’s name, base state, appearance, production source file, source line, pixel dimensions, scale, filename, capture method, and window level.
- `contact_sheet.png` contains every rendered image with its name below its thumbnail.
- `isolation-before.json` and `isolation-after.json` record protected paths, modification times, and regular file sizes. Paths under the home directory use a tilde.
- Standard error records fixture creation, each completed capture, the verified window level, and the final isolation result.

The renderer uses activation policy `prohibited`. Render windows cannot become key or main windows, ignore mouse events, and stay one level below the desktop window. The renderer verifies both its activation policy and the WindowServer level before capture. Standard window states include native title bars and toolbars. Tall expanded states use borderless windows so macOS does not constrain their height to the display.

When Screen Recording access already exists, the renderer captures only its own verified window with `screencapture -l`. It never requests permission or captures a display. Without that access, it uses AppKit `cacheDisplay`. Native vibrancy and video layers have more complete rendering through the window capture method; the manifest identifies the method used.

## Fixture Isolation

`UpshotStorage` routes direct defaults access to a unique render suite. The SwiftUI root supplies the same suite through `defaultAppStorage`. History, recording projects, wallpapers, the Library index, exports, the agent socket path, and the configuration path resolve inside a temporary fixture directory. Normal launches retain their existing storage locations.

The fixture generator creates screenshots, a GIF, screen and camera movies, narration audio, a recording manifest, pointer events, and recording project metadata. Production views receive those files and deterministic view state. Rendering disables hardware device discovery, live source discovery, OCR work, cloud connection requests, Keychain access, and updater construction. Overlay presenters are never called to display overlays; their views render inside the renderer’s windows.

The renderer compares the real Application Support tree, configuration directory, and regular and Dev defaults files before and after rendering. An observed modification changes the run to a failure. Successful runs remove the fixture directory and render defaults domain before exiting.

## Coverage

- Settings: General, Screenshots, Screen Recordings, Overlay, MCP, Cloud, and About; expanded panes; all keyboard shortcuts; each composed settings section; missing permissions; disabled MCP; configured, connected, and failed Cloud states.
- Library: grid, list, empty, search results, empty search results, screenshot and recording filters, selected capture inspector, and multiple selection inspector.
- Annotation editor: every annotation tool, generated annotations, clean image, crop, background inspector, border, camera, progressive blur, color adjustments, watermark, background picker, load failure, and New Style popover.
- Studio: Look, selected zoom, selected layout, selected text, selected redaction, selected image, selected audio, Captions, transcript editing, crop, export progress, export failure, and share failure; expanded inspector controls; video and GIF export options; audio export options; New Style and Share Options popovers.
- Quick Access: one card, several cards, hover actions, tucked handle, image and video cards, compression and preparation activity, copied link, failed upload, compressed result, and failed action.
- Pinned screenshots: default, hover toolbar, and square corners.
- Capture History: every filter and the empty strip.
- Screenshot selection: area, window, element, crosshair with magnifier, and every All-In-One mode, drawn over a generated image.
- Scrolling capture: manual ready, automatic ready, running, and finishing controls.
- Recording: picker, teleprompter editor, visible-window reminder, selected area, recording, paused, starting, finishing, each countdown value, area selection and dragging, outside-area dimming, live pen, notch and pill teleprompters, display and window source targeting, and camera preview.
- Feedback: copied text, no text, failed text recognition, QR codes, barcodes, links, and combined codes and links.
- Menu bar: main menu content, capture actions, recording controls, recent captures, and recording projects.
- App alerts: editor save decisions, Library rename and deletion, cloud deletion, style deletion, watermark import failure, media import failure, capture naming, recording input warnings, recording failures, recording recovery, permission explanations, automation confirmation and failure, screenshots folder failure, and quit decisions.

Quick Look screenshot and recording previews use generated fixture files in an embedded Quick Look view. The native Quick Look panel, macOS file and color chooser panels, and Sparkle update windows remain outside the catalog. Quick Look content uses the embedded preview view. These system and updater presentations do not have fixture-safe adapters in the renderer.

## Add a State

Add a `StateRenderDefinition` in `StateRenderCatalog` or `StateRenderSupplementalCatalog`. Use a unique filename-safe base name, the production source filename, a source marker, a layout size in points, and a factory returning the production view. The factory may load generated fixture media asynchronously. An optional scroll fraction captures lower portions of a scroll view.

Use fixture models and the existing render-only construction methods. For a new overlay, expose its view separately from the presenter. The factory must not call a presenter that opens windows, captures pixels, activates the app, reads production data, or starts hardware services. Render-only methods must assert `UpshotStorage.isRenderingStates`.

Regenerate the embedded source locations after editing production source files:

```bash
node scripts/update-render-state-sources.mjs
```

The embedded locations let an installed app write source references without reading a source checkout. Rebuild, run the selected state, and inspect both PNGs at full size. Check the manifest dimensions, capture method, and below-desktop level. Run the complete catalog after changes that affect fixture construction, shared storage, appearance, or capture.
