---
review_status: unreviewed
approval_status: not_approved
sources:
  - Upshot working tree at aa518e6 on 2026-11-17
  - webadderallorg/Recordly at 1a2ea26 (2026-11-17), cloned to .local/reference/Recordly
  - Recordly GitHub releases v1.0.0 through v1.4.0
method: static code reading by twelve Grok 4.7 research agents, one per Recordly area, then one Grok 4.7 verification agent per report, then four GPT-6.1 Sol agents that rechecked every report against both repositories; nothing built or run
detail_reports: .local/recordly-port-research/
---

# Recordly Feature Gaps

Recordly is an Electron screen recorder and demo-video editor with 36,974 GitHub stars and about 223,000 lines of TypeScript. Each item below is a Recordly feature that Upshot lacks or implements only in part. The full behavior, the Recordly implementation with file and line citations, the Upshot code that exists today, a port specification, and an effort estimate for every item are in the detail report for its area in `.local/recordly-port-research/`.

The twelve reports hold 187 features. Upshot already has 19 of them at comparable depth. Of the remaining 168, the reports rate 61 High value for demo-video quality, 69 Medium, and 38 Low. A feature whose Recordly code exists but appears on no Recordly screen is rated Low. After merging the two aspect ratio features into one, the 60 High-value gaps are the list below.

Effort is Small for under a day, Medium for one to three days, and Large for more than three days.

## Zoom and Camera Motion

Report: `.local/recordly-port-research/zoom-and-camera-motion.md`

- Classified click zoom suggestions, Absent, Large: Recordly sorts recorded pointer activity into clicks, typing, and text selection and builds zoom blocks only from click-like moments. Upshot keeps pointer-down presses that fall before the last second and land inside the frame, starts each cue 0.3 s before the press and ends it 2.5 s after, with the end also capped 0.8 s before the recording ends, and joins a cue when its start falls within 2.5 s of the previous cue's end.
- Separate zoom-in and zoom-out durations, Absent, Large: every Recordly zoom block has its own zoom-in and zoom-out timing. Upshot uses one spring for scale and position in both directions.
- Connected neighboring zooms, Absent, Medium: Recordly pans the camera straight from one zoom to the next instead of zooming out between them. Upshot zooms out across any gap between cues.
- Safe-zone cursor follow, Partial, Medium: Recordly holds the camera still until the cursor leaves an inner region, then moves only the axis the cursor left on. Upshot's Pointer mode follows the latest pointer sample, or the next press when that press is within 0.5 s, and its Smart mode holds the center of each activity region.
- Focused and Cinematic motion presets, Partial, Medium: one Recordly choice sets zoom timing, cursor size, smoothing, and click bounce together. Upshot's Smooth and Dynamic switch changes only the zoom spring.
- Automatic zooms on a fresh recording, Partial, Medium: Recordly has a setting to add zoom suggestions to every new recording, default on. Upshot always adds them to a recording that has no saved edit, with no setting.
- Pan and radial screen motion blur, Partial, Large: Recordly blurs along the pan direction while panning and outward from the center while zooming, in preview and export. Upshot blurs by blending sampled frames at export only.
- Discrete zoom depth, Partial, Small: Recordly offers six fixed zoom amounts, 1.25× to 5×, default 1.8×. Upshot has a slider from 1.1× to 3×, default 1.5×.
- Auto and manual zoom tracking, Partial, Medium: Recordly's Auto mode follows the cursor through the safe zone, and its Manual mode holds a fixed point. Upshot has Pointer, Smart, and Fixed modes without the safe zone.

## Cursor

Report: `.local/recordly-port-research/cursor-rendering.md`

- Cursor style sets, Partial, Large: Recordly ships eight full cursor sets, including Windows 11, Linux, Touch dot, Minimal, and Pixel Glove, each with artwork for every pointer shape. Upshot has seven styles drawn as vector shapes.
- Cursor smoothing, Partial, Large: Recordly stores one smoothing amount, 0.67, on both presets, has no smoothing slider, changes the feel through spring multipliers, drops cursor-type runs shorter than 500 ms, and straightens the path only on the Cinematic preset. Upshot uses a glide spring for ordinary travel, an intercept spring within 0.175 s of a press, and a track spring while dragging, with no smoothing slider and no path straightening.
- Click effects, Partial, Medium: Recordly offers spotlight, ripple, echo, and burst click effects in ten colors. Upshot has one on-or-off click highlight.

## Timeline Editing

Report: `.local/recordly-port-research/timeline-editing.md`

- Drag reorder of clips, Absent, Large: Recordly lets the user drag a clip to a new place in the sequence. Upshot always plays clips in source order.
- Per-clip speed, Partial, Medium: Recordly clip speed runs from 0.25× to 30× in preview. Upshot runs from 1× to 8×, so Upshot has no slow motion.
- Edge trim of a clip, Partial, Medium: Recordly lets a clip end be dragged out again to bring back footage that was trimmed away. Upshot's trim stops at the neighboring clip's edge.
- Split at the playhead, Partial, Medium: Recordly splits with a configurable Command-B, keeps the left half selected, and splits any zoom that covers the split point. Upshot selects the right half, splits with a fixed Command-B, and also splits the clip lane on c at the hover time and on s at the playhead, and it leaves a covering zoom whole.
- Delete a clip, Partial, Small: Recordly can delete any clip, including the last one. Upshot refuses to delete the last clip.
- Effects follow edited footage, Partial, Medium: when clips are trimmed, sped up, reordered, or deleted, Recordly moves zooms and annotations so they stay on the same footage, and splits an effect in two when its footage is no longer continuous. Upshot converts times for some edits only.
- Clips placed in any order, Partial, Large: Recordly stores the clips as a sequence the user arranges, so a clip's place on the timeline is independent of where its footage sits in the recording. Upshot sorts clips by their position in the recording.

## Backgrounds and Frame

Report: `.local/recordly-port-research/frame-styling-and-backgrounds.md`

- Video wallpapers, Absent, Large: Recordly can use a looping video, built-in or imported, as the background. Upshot backgrounds are images, colors, and gradients only.
- Current desktop wallpaper, Absent, Medium: Recordly's default background is the user's current macOS desktop picture, including moving aerial wallpapers. The Upshot Studio has no such option.
- Background blur, Absent, Medium: Recordly can blur the wallpaper from 0 to 8 px. The Upshot Studio has no background blur.
- Image wallpapers, Partial, Medium: Recordly ships a bundled wallpaper gallery and keeps imported images in it. Upshot keeps up to 24 recent image files, installs the UIHSSN and Fayazara still packs, and searches Unsplash when an access key is set.
- Output aspect ratio, Partial, Medium: Recordly offers 16:9, 9:16, 1:1, 4:3, 4:5, 16:10, 10:16, and any custom ratio. Upshot offers Original, 16:9, 9:16, 1:1, and 4:5.
- Frame padding, Partial, Medium: Recordly sets padding for each side separately, up to 100 percent. Upshot has one padding value, up to 18 percent.
- Gradient backgrounds, Partial, Medium: Recordly lets the user build a gradient with any angle and two to five colors. Upshot offers sixteen fixed gradients.
- Frame shadow, Partial, Small: Recordly draws a two-layer shadow whose size follows the output size. Upshot has one shadow value.

## Webcam

Report: `.local/recordly-port-research/webcam-overlay.md`

- Webcam picture crop, Absent, Medium: Recordly lets the user drag a crop box over the webcam picture. Upshot always fills the bubble from the whole camera picture.
- Uploaded webcam footage, Absent, Medium: Recordly can use any video file as the webcam layer. Upshot uses only the camera it recorded.
- Position presets and custom placement, Partial, Medium: Recordly offers a 3 by 3 grid of positions plus dragging to any spot. Upshot offers four corners.
- Bubble size and shape, Partial, Medium: Recordly offers circle, rounded square, and rectangle at any size. Upshot offers circle, square, and portrait 3:4.
- Soft-blur frame, Partial, Medium: Recordly's default bubble edge fades the outer 16 px of the picture into a blur. Upshot draws a thin white outline.
- Bubble that shrinks during zoom, Partial, Small: Recordly shrinks the bubble by a fixed formula as the zoom deepens. Upshot shrinks it by a set amount.
- Camera capture and device choice, Partial, Small: Recordly remembers the chosen camera across launches and picks another camera when that one is unplugged. Upshot stores one camera ID.

## Audio

Report: `.local/recordly-port-research/audio.md`

- Clip mute, Absent, Medium: Recordly can mute the sound of one clip and keep its picture. Upshot has no mute for a clip.

## Captions

Report: `.local/recordly-port-research/captions-and-transcription.md`

- Microphone and system audio merge, Absent, Medium: Recordly transcribes the microphone and the system audio separately and combines the results. Upshot transcribes one audio track.
- On-device speech recognition, Partial, Small: Recordly offers Parakeet and two Whisper models for 25 or more languages. Upshot uses Apple's SpeechAnalyzer in one language.
- Phrase splitting and silence handling, Partial, Medium: Recordly splits captions at pauses of 700 ms or more, at sentence ends, and at silences of 1.5 s or more, and drops words the recognizer made up during silence. Upshot splits at 42 characters or 4 seconds.
- Caption style presets, Partial, Medium: Recordly offers named caption looks, Reveal and Classic plus six more. Upshot has one caption bar style.
- Word highlight and word reveal, Partial, Medium: Recordly can highlight the spoken word or reveal words one at a time as they are spoken. Upshot highlights the spoken word.
- Caption layout and motion, Partial, Large: Recordly controls font size, rows, bottom offset, width, box radius, background opacity, text color, and caption animation. Upshot controls position and size.
- Captions in preview and export, Partial, Small: Recordly shows the same styled captions in preview and export and lets the user edit a caption by double-clicking it. Upshot shows a caption bar with no editing on the preview.

## Annotations and Redaction

Report: `.local/recordly-port-research/annotations-overlays-and-redaction.md`

- Solid-color redaction fill, Absent, Medium: Recordly can cover a region with a solid color instead of a blur. Upshot redaction is pixelate or blur only.
- Arrow callouts, Absent, Medium: Recordly offers arrow annotations in eight directions with color, stroke width, and timing. The Upshot Studio has no arrow annotation.
- Annotations follow the camera, Partial, Medium: Recordly text and image annotations move and scale with zooms, so a callout stays on its button. Upshot redactions follow zooms, but Upshot text and images stay fixed on the canvas.

## Export

Report: `.local/recordly-port-research/export.md`

- Resolution tiers, Partial, Medium: Recordly offers 720p, 1080p, 1440p, 4K, original size, and custom pixel sizes. Upshot offers original, 1080p, 720p, and 480p.
- Frame rate, Partial, Small: Recordly offers 24, 30, and 60 frames per second. Upshot offers 30 and 60.
- Encoding mode, Partial, Medium: Recordly offers Fast, Balanced, and Quality encoding. Upshot offers High, Medium, and Low quality.
- GIF export controls, Partial, Medium: Recordly offers GIF size limits of 720p, 1080p, and original, frame rates of 15, 20, 25, and 30, and a loop switch. Upshot always writes a continuous loop, and sizes a GIF with the same Original, 1080p, 720p, and 480p height caps as video, plus frame rates of 10, 15, 20, 25, and 30 and Low, Medium, and High posterize quality.

## Recording

Report: `.local/recordly-port-research/recording-and-capture-controls.md`

- Editor opens while the recording finishes, Partial, Medium: Recordly opens the editor while the recording file is still being written. Upshot opens it after the file is imported.
- Countdown that prepares the recorder, Partial, Medium: Recordly starts the recorder during the countdown so recording begins the moment the countdown ends, and offers 0, 3, 5, and 10 seconds. Upshot starts the recorder after the countdown and offers 0, 1, 3, and 5 seconds.
- Window crop, follow, and close, Partial, Large: a Recordly window recording includes menus and popovers over the window, follows the window to another display, and stops when the window closes. Upshot records the window by itself.
- Full-screen capture picker, Partial, Medium: Recordly's picker uses a blue highlight and dims the rest of the screen. Upshot already highlights the display or window under the pointer and starts recording on click.
- Dim outside the recorded target, Partial, Medium: Recordly always dims everything outside the recording. Upshot has the same dimming as a setting that is off by default.
- Recording controls kept out of the movie, Partial, Small: Recordly keeps its control bar out of the recording and lets clicks pass through it. Upshot's control bar differs in window level and click handling.

## Projects, Library, and Sharing

Report: `.local/recordly-port-research/projects-library-sharing-and-editor-shell.md`

- Five-second hover preview, Absent, Large: hovering a Recordly project card plays the edited video, muted, for five seconds. Upshot shows a still.
- Upload while the export is still writing, Absent, Large: Recordly starts uploading a share link while the MP4 is still being written. Upshot uploads after the export finishes.
- Composed project thumbnails, Partial, Medium: Recordly project cards show a still of the edited video with wallpaper and frame. Upshot shows the exported file or the raw recording.
- Cloud share link, Partial, Medium: Recordly's share form takes a title of up to 200 characters and notes of up to 2000 characters, and its success state plays the published video. Upshot's share form takes a title and a comments switch, then uploads the current edit and copies the link, with no notes field and no published preview.
- Project file format and reopening, Partial, Medium: a Recordly project file holds the full edit plus undo history and reopens it. An Upshot project package holds the edit without undo history.

## Features Recordly Announced as Extensions

Report: `.local/recordly-port-research/extensions-and-release-history.md`

Recordly removed its extension system on 2026-08-28 in commit `c574fd8d99`, and its marketplace site returned an error on 2026-11-17. Device frames, browser mockups, cursor click sounds, and extension wallpapers were announced in Recordly v1.1.21 as extension ideas. None of the four exists in the current Recordly build, so the extension report rates each one Low as a port candidate.

## Medium and Low Value Gaps

Each report lists its Medium and Low gaps in the same format. Examples: Pixel Glove cursor, cursor motion blur, loop cursor, timeline keyframe markers, timeline snapping, clip merge, stacked audio lanes, microphone level meters, subtitle files such as SRT, caption contrast and outline, GIF size optimization, file size estimate, failed export recovery, project folders, relinking a missing recording, keyboard shortcut customization, and Light and Dark appearance.

## Not Ported

Each report ends with a Not Portable section. Its items exist only because Recordly is a cross-platform Electron app: the Windows and Linux capture helpers, NVIDIA CUDA export, ffmpeg distribution, the Microsoft Store build, and translation plumbing. Accounts, billing, and sign-in are out of scope.
