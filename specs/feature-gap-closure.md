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

- A, Area Selection. Owns `ScreenshotManager.swift`, `CaptureCoordinator.swift`, and `TextCaptureSelection.swift`, which it generalizes into the area selector for every area capture. Delivers: own selector with frozen screen, crosshair and magnifier, capture previous area for screenshots, selection spanning several displays, smart element capture through Accessibility, and All-In-One capture mode.
- B, Screenshot Output. Owns `ScreenshotFileNaming.swift` and new post-processing files. Delivers: sRGB conversion, Retina 1x scaling, 1px border, @2x suffix, cursor on screenshots, background preset on every screenshot with Shift to skip, wallpaper or transparent window background with padding, hide desktop icons while capturing, filename templates, ask for name after capture, and clipboard mode.
- C, Text Recognition. Owns `ImageTextRecognizer.swift` and every OCR caller's error path. Delivers: QR and barcode detection with link prompts, contrast and vertical CJK retry passes, VisionKit Live Text before Vision, recognition language, keep line breaks, detect links, and distinct capture and recognition errors in every caller.
- D, Annotation Editor. Owns `Annotation*.swift` and `Engine/`. Delivers: callout and label text styles, highlighter with text snapping, measure tool, watermark, combine images, additional blur styles, color grading, rotate, flip, inverse arrow with Option, smooth drawing, object shadows, automatically expanding canvas, always on top, and color names.
- E, Quick Access and Pins. Owns `CaptureShelf*.swift` and `PinnedScreenshotPresenter.swift`. Delivers: overlay size, auto-close action, Option-drag to keep, keeping the card on a cancelled drag, close after uploading, hover single-key shortcuts, swipe actions, and pinned screenshot corners, shadow, and border.
- F, Capture History. Owns `ScreenshotHistoryStore.swift` and new history strip files. Delivers: full-width recent captures strip with All, Screenshots, Videos, GIFs, and Video Projects filters and Restore, restore last capture, and history retention.
- G, Recording Export. Owns `RecordingExport*.swift`, `RecordingStudioExporter.swift`, and `RecordingStudio*Inspector.swift`. Delivers: GIF export with frame rate, resolution, and quality, Retina 1x video, mono audio, separate audio tracks, motion blur levels, Smooth and Dynamic zoom styles, keystroke size, style, nine positions, and key filter, 3D shots, and aspect reframing.
- H, Live Recording. Owns `RecordingBar*.swift`, `RecordingControlPresenter.swift`, and `ScreenRecordingManager.swift`. Delivers: recording time in the menu bar, dim screen while recording, Do Not Disturb while recording, and live pen annotation during recording.
- I, Automation. Owns the hotkey, menu, and app entry files. Delivers in phase one: URL scheme, `upshot` capture CLI over the existing socket, searchable shortcut catalog, and `~/.config/upshot/config.toml`.

## Phase Two

Gated on phase one. Runs one agent at a time on `~/github/upshot` itself.

- Scrolling capture, built on workstream A's selector.
- Workstream I wires every new action into shortcuts, the menu, the URL scheme, and the CLI.
- The integrating agent places every settings section into its pane and rebuilds.

## Verification

Build success proves nothing. Each feature needs one of these as evidence:

- Window captures with `screencapture -l` of the Upshot Settings, Library, editor, and Studio windows, which do not take over the display.
- Exported files, such as a GIF from a Studio project exported through the MCP tools, inspected frame by frame.
- Log lines from the running Upshot app. The human user is never asked to use the Upshot Dev build.
- For features that cover the whole screen, such as the area selector, the history strip, and dim screen, a test session run by the user, with the agent reading the logs afterwards.

Each workstream's final diff and evidence go to an independent review by `gpt-6-luna` before integration. The integrating agent rejects findings that expand scope.
