---
review_status: unreviewed
approval_status: not_approved
sources:
  - Upshot, forked from fayazara/screendrop at c262c1a (v0.38.0), plus the uncommitted Capture Text changes
  - ~/github/reference_apps/Snapzy (duongductrong/Snapzy, v2.2.0-beta.10)
  - ~/github/reference_apps/better-shot (KartikLabhshetwar/better-shot, v0.5.9)
method: static code reading by three subagents; nothing built or run
---

# Screenshot App Feature Comparison

## Repository Facts

- Upshot, from upstream Screendrop: 2,396 stars, 237 Swift files, about 75,700 lines, macOS 26.0 target, Sparkle and DockProgress, last release v0.38.0 on 2026-11-10.
- Snapzy: 3,563 stars, 865 Swift files, about 241,600 lines, macOS 13.0 target, Sparkle, GRDB, Swift-WebP, swift-argument-parser, last release v2.2.0-beta.10 on 2026-11-10.
- Better Shot: 2,450 stars, 264 Swift files, about 68,100 lines, macOS 14.0 target, DockProgress, custom GitHub updater, last release v0.5.9 on 2026-10-11, last push 2026-10-24.

## Screenshot Capture

- Scrolling capture: Snapzy implemented, with manual and auto-scroll and Vision-verified stitching. Better Shot implemented, using a dlsym-resolved private symbol and hidden tuning keys. Upshot absent.
- Freeze screen before selection: Snapzy opt-in for all area captures. Better Shot opt-in, own selector only. Upshot only in the uncommitted Capture Text change.
- Capture previous area: Snapzy and Better Shot implemented for screenshots. Upshot only for area recordings.
- Own area selector: Snapzy and Better Shot draw their own. Upshot calls `screencapture -i`.
- Multi-display area spanning: Snapzy composites every intersecting display. Better Shot and Upshot are limited to one display.
- Smart element capture through Accessibility: Snapzy only.
- Object cutout, color picker, screen ruler: Snapzy has all three. Better Shot has the color picker. Upshot has none.

## Text Recognition

- Engine: all three use Apple Vision. Snapzy adds contrast-enhanced and vertical CJK retry passes and an optional OpenAI-compatible remote engine. Better Shot tries VisionKit Live Text first, then Vision.
- Error reporting: Upshot committed code reports every failure as "No text found"; the uncommitted change separates the failure cases. Better Shot reports "Couldn't recognize text". Snapzy capture OCR also hides errors as "no text found".
- QR codes: Snapzy QR only, with link prompts. Better Shot all default barcode symbologies. Upshot absent.
- Smart redaction: all three.

## Annotation Editor

- All three have arrows, shapes, text, counters, blur and pixelate, spotlight, crop, backgrounds, padding, shadow, and 3D card tilt.
- Snapzy adds callout and label text styles, a highlighter with text snapping, a measure tool, a watermark, combine images, and eight blur styles.
- Better Shot adds color grading, rotate, and flip.
- Upshot adds progressive blur, Unsplash backgrounds, and exportable presets.

## Post-Capture Overlay

- All three have a floating card stack, drag-out, pin to screen, and auto-dismiss with hover pause.
- Snapzy adds hover single-key shortcuts and configurable swipe actions.
- Upshot dismisses a card on any drag end, including a cancelled drag, when "Close after dragging" is on.

## Screen Recording

- Upshot and Better Shot both have a studio editor with a synthetic cursor, auto-zoom from clicks, keystroke display, camera layouts, transcription, filler-word removal, and teleprompter. Upshot adds camera cutout, face touch-up, text, image, and GIF overlays, and video redaction. Better Shot adds 3D shots and aspect reframing.
- Snapzy has a simpler editor with trim, speed, auto-focus zoom, and live pen annotation during recording.
- GIF export: Snapzy only, as a recording output mode.

## Sharing and Storage

- Upshot: self-hosted Cloudflare Worker, which is not in the repository, plus a Library with Vision feature-print similarity search and Apple Intelligence categories.
- Snapzy: S3, R2, and Google Drive, with expiry and encrypted credential transfer, and GRDB history.
- Better Shot: direct R2 upload plus a stateless Next.js share viewer.
- Filename templates: Snapzy and Better Shot have token templates. Upshot uses a fixed `Upshot_` timestamp name.

## Automation

- URL scheme: Snapzy has about 40 routes. Better Shot has 8 routes. Upshot has none.
- CLI: Snapzy ships a `snapzy` CLI over a Unix socket. Upshot has only `--mcp`. Better Shot has none.
- App Intents: only Upshot, with 7 intents.
- MCP server: only Upshot, with 21 tools.
- Shortcut customization: Better Shot has 81 bindable actions. Snapzy has 23 global actions plus single-key tools. Upshot has 5 global hotkeys.
- Configuration file: Snapzy has `~/.config/snapzy/config.toml`.

## Upshot Gaps Present in at Least One Other App

- Scrolling capture
- Freeze screen for every area capture, with its own selector
- Capture previous screenshot area
- Multi-display area spanning
- QR code detection
- OCR retry passes and correct error reporting in every OCR caller
- URL scheme
- CLI capture commands
- Filename templates
- Expanded shortcut catalog
- Smart element capture, color picker, and screen ruler
- GIF export
- Additional cloud backends
