---
review_status: unreviewed
approval_status: not_approved
reference_app: CleanShot X 5.0.2 (Setapp build 0e44768)
reference_screenshots: .local/reference/cleanshot_x/ (local only, captured 2026-11-12)
upshot_baseline: commit 237bebb, plus the uncommitted Capture Text changes
---

# CleanShot X Feature Parity

This list records every setting and control visible in the CleanShot X screenshots and the matching Upshot behavior. It is a reference for choosing features and design. Inclusion here does not mean a feature is wanted.

Upshot status uses three values. Present means the Upshot source implements it. Partial means the source implements part of it or a different form of it. Not found means the code inventory of Upshot found no implementation.

## General

- Launch at login: present, through SMAppService.
- Show menu bar icon: present.
- Hide desktop icons while capturing: not found.
- Play sounds: present.
- Shutter sound choice: partial. Upshot plays the system screen-capture sound and has no choice of sound.
- Export location: present. The default is ~/Pictures/Upshot.
- After Capture matrix, with separate Screenshot and Recording columns for Show Quick Access Overlay, Copy file to clipboard, Save, Upload to Cloud and copy link, Open Annotate tool, Pin to the screen, and Open Video Editor: present. Upshot has the same per-type matrix, with Open in Studio in place of Open Video Editor.

## Shortcuts

- Searchable shortcut list: not found. Upshot has five global hotkeys with a recorder, conflict check, and per-action reset.
- All-In-One capture mode, default Shift-Command-5: not found.
- Toggle Desktop Icons: not found.
- Open Capture History: not found as a shortcut. Upshot has a Library window, opened with Command-Shift-L inside the app.
- Restore Last Capture: not found.
- Capture Area, Capture Fullscreen, Capture Window: present.
- Capture Previous Area: not found for screenshots. Upshot restores the previous area only for area recordings.
- Self-Timer shortcut: not found. Upshot has a self-timer setting.
- Capture Area and Copy to Clipboard, Capture Area and Save, Capture Area and Upload to Cloud: not found as separate actions.

## Quick Access

- Position on screen, left or right: present, as bottom left or bottom right.
- Move to active screen: partial. The Upshot shelf docks on the display where the capture happened.
- Overlay size slider: not found.
- Auto-close with an interval: present, with Never, 5, 10, 30, and 60 seconds.
- Auto-close action such as Save and Close: not found.
- Close after dragging, with Option held to keep the item: partial. Upshot closes after dragging, also closes on a cancelled drag, and has no Option override.
- Close after uploading: not found.
- Save button behavior, save to the export location or choose a destination: present, as "Save without choosing a location".

## Wallpaper

- Custom wallpaper used to hide desktop icons and as the background behind window screenshots: not found.
- Update wallpaper when switching Spaces: not found.

## Screenshots

- File format: present, with PNG, JPEG, and HEIC.
- Convert to sRGB profile: not found.
- Scale Retina screenshots to 1x: not found.
- Add 1px border to all screenshots: not found.
- Background preset applied to every screenshot, skipped while Shift is held: not found. Upshot has background presets inside the annotation editor only.
- Self-Timer interval: present, with Off, 3, 5, and 10 seconds.
- Show cursor on screenshots: not found.
- Freeze screen when taking a screenshot: partial. Only the uncommitted Capture Text change freezes the screen.
- Window screenshot background, with wallpaper or transparent, and padding: not found.
- Capture window shadow: present.
- Crosshair mode and magnifier: not found. Upshot uses the macOS selection tool.

## Screen Recording

- Show controls while recording: present.
- Remember last selection: present.
- Display recording time in menu bar: not found.
- Dim screen while recording: not found.
- Show countdown: present, as a start delay of Off, 1, 3, or 5 seconds.
- Do Not Disturb while recording: not found.
- Show cursor: present, as a synthetic cursor with seven styles.
- Highlight clicks with options: present.
- Show keystrokes with options: present.
- Frame rate: present, with 30 or 60 fps on export.
- Max resolution: present, with Original, 1080p, 720p, and 480p on export.
- Scale Retina videos to 1x: not found.
- Record audio in mono: not found.
- Record system audio: present.
- Audio tracks, single or separate: not found. Upshot records the camera to its own file.
- GIF frame rate, resolution, optimization, and quality: not found. Upshot has no GIF export.

## Annotate

- Inverse arrow direction, toggled with Option: not found.
- Smooth drawing: not found.
- Remember if background tool was opened: not found.
- Draw shadow on objects: not found.
- Automatically expand canvas: not found.
- Always on top: not found.
- Show Dock icon for the editor: not found. Upshot has an app-wide Dock icon setting.
- Show color names: not found.

## Cloud

- Hosted CleanShot Cloud account with sign in: not found. Upshot uploads to a self-hosted Cloudflare Worker deployed from fayazara/screendrop-worker.

## Advanced

- Ask for name after every capture: not found.
- File name format customization: not found. Upshot uses a fixed Upshot_ timestamp name.
- Add @2x suffix to Retina screenshots: not found.
- Copy to clipboard mode, such as File and Image: not found.
- Keep history for a set number of days: not found. Upshot keeps history without a retention setting.
- Text recognition language: not found. Upshot uses the Vision default languages.
- Keep line breaks in recognized text: not found as a setting.
- Detect links in recognized text: not found.
- All-In-One remember last selection: not found.
- Pinned screenshot rounded corners, shadow, and border: not found.
- Allow URL scheme API: not found. Upshot has no URL scheme.
- Reset all warning dialogs: not found.

## About

- Links to website, changelog, contact, X, and YouTube: partial. Upshot's About pane links to the original author's X account.
- Share usage statistics: not found. Upshot has no analytics.

## Capture History Overlay

- Full-width strip of recent captures across the top of the screen, filtered by All, Screenshots, Videos, GIFs, and Video Projects, with Restore on the selected item: not found. Upshot has a Library window and a Recent Captures menu.

## Recording Toolbar

- Settings button, width and height fields, fullscreen toggle, and crop: partial. Upshot has an area picker with an aspect lock.
- Microphone, system audio, camera, click highlight, and keystroke toggles: present in the Upshot picker bar.
- Record GIF with Option-Return: not found.
- Record Video with Return: present.
- Record in Studio Mode: partial. Upshot always records for its Studio editor.

## Recording Control Bar

- Stop button with elapsed time: present.
- Pause: present.
- Restart: present.
- Delete: present, as Discard recording.
- Drag handle: partial. The Upshot bar moves when dragged by its background and has no separate handle.

## Video Editor

The CleanShot X video editor is one window with a tool rail on the left, an inspector panel for the selected tool, a preview, transport controls, and a timeline with a zoom lane above a thumbnail lane. Export and cloud upload buttons sit in the title bar.

- Keystrokes inspector, with size, dark or light style, a nine-position grid, and a choice between command keys only and all keys: partial. Upshot draws keystrokes on export with a placement setting and records only special keys and modifier shortcuts, so typed text never appears.
- Audio inspector, with the recorded microphone and an Include system audio toggle: partial. Upshot has an audio toggle on export and supports imported audio clips.
- Camera inspector: present. Upshot has camera layouts, shapes, cutout, and face touch-up.
- Background inspector, with gradients, wallpapers, custom wallpapers, plain colors, aspect ratio, padding, shadow, and corners: present. The Studio uses the annotation background system.
- Motion blur level, Low to High: partial. Upshot has a motion blur on or off toggle in the export options.
- Zoom animation style, Smooth or Dynamic: not found. Upshot uses one spring profile for every zoom.
- Zoom segments on their own timeline lane, labeled with the zoom level: present.
- Cut tool: present, as split, trim, and delete on the clip timeline.
- Timeline zoom slider: present, with zoom in and zoom out buttons.
- Export and cloud upload buttons in the title bar: present, through the Studio export options and upload actions.
