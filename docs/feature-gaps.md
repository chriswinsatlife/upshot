---
review_status: unreviewed
approval_status: not_approved
sources:
  - docs/cleanshot-x-feature-parity.md
  - docs/snapzy-better-shot-comparison.md
---

# Feature Gaps

Each item is a feature that Upshot lacks, or implements only in part, and that at least one of CleanShot X, Snapzy, or Better Shot has. The apps that have the feature follow the colon. Listing a gap does not mean the feature is wanted.

## Screenshot Capture

- All-In-One capture mode: CleanShot X.
- Scrolling capture: Snapzy and Better Shot.
- Own area selector in place of `screencapture -i`: Snapzy and Better Shot.
- Freeze screen for every area capture: CleanShot X, Snapzy, and Better Shot. Upshot freezes the screen only in the uncommitted Capture Text change.
- Crosshair mode and magnifier: CleanShot X.
- Capture previous screenshot area: CleanShot X, Snapzy, and Better Shot. Upshot restores the previous area only for area recordings.
- Area selection spanning several displays: Snapzy.
- Smart element capture through Accessibility: Snapzy.
- Hide desktop icons while capturing, and a Toggle Desktop Icons shortcut: CleanShot X.
- Custom wallpaper behind window screenshots, and a transparent or padded window background: CleanShot X.
- Show cursor on screenshots: CleanShot X.
- Background preset applied to every screenshot: CleanShot X. Upshot has background presets inside the annotation editor only.
- Convert to sRGB, scale Retina screenshots to 1x, add a 1px border, and add an @2x suffix: CleanShot X.
- Color picker: Snapzy and Better Shot.
- Screen ruler and object cutout: Snapzy.

## Text Recognition

- QR and barcode detection: Snapzy and Better Shot.
- Contrast-enhanced and vertical CJK retry passes: Snapzy.
- Optional remote OCR engine: Snapzy.
- VisionKit Live Text before Vision: Better Shot.
- Distinct error messages for capture and recognition failures: Better Shot. Upshot has them only in the uncommitted Capture Text change.
- Recognition language, keep line breaks, and detect links settings: CleanShot X.

## Annotation Editor

- Callout and label text styles, highlighter with text snapping, measure tool, watermark, combine images, and eight blur styles: Snapzy.
- Color grading, rotate, and flip: Better Shot.
- Inverse arrow direction, smooth drawing, shadow on objects, automatically expand canvas, always on top, and color names: CleanShot X.

## Quick Access Overlay

- Overlay size setting: CleanShot X.
- Auto-close action such as Save and Close, and close after uploading: CleanShot X.
- Option-drag to keep the item after dragging: CleanShot X. Upshot also closes the card on a cancelled drag.
- Hover single-key shortcuts and configurable swipe actions: Snapzy.
- Pinned screenshot rounded corners, shadow, and border settings: CleanShot X.

## Capture History

- Full-width strip of recent captures with filters and Restore: CleanShot X. Upshot has a Library window and a Recent Captures menu.
- Restore Last Capture and Open Capture History shortcuts: CleanShot X.
- History retention period: CleanShot X.

## Screen Recording

- GIF export with frame rate, resolution, and quality settings: CleanShot X and Snapzy.
- Recording time in the menu bar, dim screen while recording, and Do Not Disturb while recording: CleanShot X.
- Scale Retina videos to 1x, mono audio, and separate audio tracks: CleanShot X.
- Motion blur levels: CleanShot X. Upshot has motion blur on or off.
- Smooth and Dynamic zoom animation styles: CleanShot X.
- Keystroke display with size, style, and nine positions: CleanShot X. Upshot has a placement setting.
- Live pen annotation during recording: Snapzy.
- 3D shots and aspect reframing: Better Shot.

## Sharing and Storage

- Hosted cloud account: CleanShot X. Upshot uploads to a self-hosted Cloudflare Worker.
- S3, R2, and Google Drive upload with link expiry: Snapzy. Direct R2 upload with a share viewer: Better Shot.
- Filename templates and ask for name after capture: CleanShot X, Snapzy, and Better Shot.
- Copy to clipboard mode setting: CleanShot X.

## Automation

- URL scheme: CleanShot X, Snapzy with about 40 routes, and Better Shot with 8 routes.
- Capture CLI: Snapzy.
- Searchable, larger shortcut catalog: CleanShot X, Better Shot with 81 bindable actions, and Snapzy with 23 global actions. Upshot has 5 global hotkeys.
- Separate Capture Area and Copy, Save, and Upload shortcuts: CleanShot X.
- Self-timer shortcut: CleanShot X.
- Configuration file: Snapzy.

## Features Only Upshot Has

- App Intents, with 7 intents.
- MCP server, with 21 tools.
- Video redaction, camera cutout, face touch-up, and text, image, and GIF overlays in the Studio editor.
- Library with Vision feature-print similarity search and Apple Intelligence categories.
- Progressive blur, Unsplash backgrounds, and exportable presets in the annotation editor.
