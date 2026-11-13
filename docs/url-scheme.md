---
review_status: unreviewed
approval_status: not_approved
---

# URL Scheme

Upshot registers the `upshot` scheme. A route has the form `upshot://capture/area`. macOS opens Upshot when necessary. The URL action uses the same action registry as global shortcuts and the socket CLI.

## Capture Routes

- `upshot://capture/fullscreen`: capture the active display.
- `upshot://capture/window`: select a window.
- `upshot://capture/area`: select an area.
- `upshot://capture/text`: select an area, recognize text, and copy the text.
- `upshot://capture/area-copy`: select an area and copy the screenshot.
- `upshot://capture/area-save`: select an area and save the screenshot in the configured export directory.
- `upshot://capture/area-upload`: select an area, upload through the configured Upshot Cloud worker, and copy the link.
- `upshot://capture/self-timer?delay=5`: select an area and capture after the specified delay. The default is five seconds. The accepted range is 1–3600 seconds. The action preserves the saved self-timer preference.
- `upshot://capture/previous-area`: invoke the area-selection workstream's previous-area callback. The phase-one build reports that integration is required until the callback is installed.

Capture routes accept `output`, an absolute destination path. Screenshot destinations require a `.png` extension. Text destinations receive UTF-8. The destination directory must exist, and existing files are preserved. Percent-encode parameter values, including spaces, `#`, `&`, and `+`.

The normal fullscreen, window, and area routes retain configured after-capture actions. The copy, save, and upload variants perform their named action without running other configured after-capture actions. The variants preserve captures in history and show a preview when the overlay preference is enabled. Upload requires existing cloud configuration.

## Recording Routes

- `upshot://recording/picker`: open the recording source picker.
- `upshot://recording/start`: start recording the active display.
- `upshot://recording/stop`: finish the active recording.
- `upshot://recording/toggle`: start or finish a recording.
- `upshot://recording/pause`: pause a recording.
- `upshot://recording/resume`: resume a paused recording.
- `upshot://recording/restart`: discard the active take and restart the same source.
- `upshot://recording/discard`: discard the active recording.

Recording controls reject incompatible recording states. Recording start and stop return after the app accepts the operation. Recording preparation and finalization continue asynchronously.

## Editor Routes

- `upshot://editor/open?path=...`: open an image in the screenshot editor.
- `upshot://editor/recording?path=...`: open a video or recording project in the recording editor.

Omitting `path` opens the latest matching capture from history. Paths may begin with `~`. Screenshot editing imports the image into capture history. Recording editing preserves the existing project-opening behavior.

## Library Routes

- `upshot://library/open`: open all captures.
- `upshot://library/screenshots`: open screenshots.
- `upshot://library/recordings`: open recordings.
- `upshot://library/restore-last`: restore the latest capture to the preview overlay.
- `upshot://library/folder`: open the configured screenshot export directory in Finder.

## Settings Routes

- `upshot://settings/general`
- `upshot://settings/screenshots`
- `upshot://settings/video`
- `upshot://settings/overlay`
- `upshot://settings/mcp`
- `upshot://settings/cloud`
- `upshot://settings/about`

## Errors and Integration

Unknown routes, duplicate parameters, unknown parameters, invalid output paths, and incompatible action states produce an app alert and a `URL scheme failed error=...` log entry. Successful actions produce `Automation action completed action=<route>`. Captures also log `Automation capture completed action=<route> path=<path>`.

`CaptureHotkeyAction` owns route names, labels, default shortcuts, and registration identifiers. Add a case and its route, label, and execution branch to expose another action to URL routing, the shortcut catalog, and `upshot actions`. The area-selection integration assigns `AutomationActions.capturePreviousArea` to an async closure returning the captured file URL.
