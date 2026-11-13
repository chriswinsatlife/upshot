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
- `upshot://capture/previous-area`: recapture the last successful screenshot area without selecting it again. A changed display arrangement makes the saved area unavailable.
- `upshot://capture/smart-element`: select an Accessibility element and capture its frame. Accessibility permission is required.
- `upshot://capture/all-in-one`: open the shared selector with Area, Window, Fullscreen, Previous Area, Element, Scrolling, and Recording modes. Scrolling retains its unavailable placeholder. Recording opens the recording controls. These two modes return acceptance without a screenshot; an `output` destination requires a screenshot.

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
- `upshot://recording/toggle-pen`: enable or disable live drawing during an active, unpaused recording.
- `upshot://recording/clear-pen`: clear the live drawing during an active, unpaused recording.

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
- `upshot://library/history`: open the Capture History strip with its media filters and Restore action.

## Settings Routes

- `upshot://settings/general`
- `upshot://settings/screenshots`
- `upshot://settings/video`
- `upshot://settings/overlay`
- `upshot://settings/mcp`
- `upshot://settings/cloud`
- `upshot://settings/about`

## Confirmation

A URL that uploads, shares, deletes, or saves changes shows a confirmation dialog before it runs. These routes are `capture/area-upload`, `editor/share`, `recording/discard`, `recording/restart`, `library/trash`, `editor/save`, `editor/done`, and `editor/recording-save`. The `upshot` command-line tool runs the same actions without a dialog, because it requires access to the local agent socket.

## Errors

Unknown routes, duplicate parameters, unknown parameters, invalid output paths, and incompatible action states produce an app alert and a `URL scheme failed error=...` log entry. Successful actions produce `Automation action completed action=<route>`. Captures also log `Automation capture completed action=<route> path=<path>`.

`CaptureHotkeyAction` owns route names, labels, default shortcuts, and registration identifiers. Add a case and its route, label, and execution branch to expose another action to URL routing, the shortcut catalog, and `upshot actions`.

## Library Selection Routes

These routes operate on the current Library selection. Open the Library and select captures first. Preview, Edit, and Rename require exactly one selected capture. Other selection routes accept several captures. Busy Library operations reject another command.

- `upshot://library/preview`: show Quick Look.
- `upshot://library/edit`: open the selected capture's editor.
- `upshot://library/rename`: open the existing rename dialog.
- `upshot://library/copy`: copy selected captures.
- `upshot://library/export`: open the existing export destination dialog.
- `upshot://library/reveal`: reveal selected captures in Finder.
- `upshot://library/trash`: open the existing Move to Trash confirmation.
- `upshot://library/refresh`: refresh the Library without requiring a selection.
- `upshot://library/copy-text`: recognize and copy text from one selected screenshot, with separate capture and recognition failure messages.
- `upshot://library/detect-codes`: detect QR codes and barcodes in one selected screenshot and present payload and link actions.

Dialog-based actions acknowledge opening the dialog. The dialog retains its existing confirmation and cancellation behavior.

## Recording Editor Controls

These routes require the recording to be open in its editor. An optional `path` selects the open recording project or video. Omitting `path` resolves the latest recording in history. Export actions acknowledge acceptance; the existing editor performs the export asynchronously.

- `upshot://editor/recording-save`: save the recording project.
- `upshot://editor/recording-undo`: undo an edit.
- `upshot://editor/recording-redo`: redo an edit.
- `upshot://editor/recording-play`: play the preview.
- `upshot://editor/recording-pause`: pause the preview.
- `upshot://editor/recording-export`: export with current editor settings.
- `upshot://editor/recording-export-gif`: select GIF delivery and export with the current GIF frame rate, quality, resolution, and optimization settings.
- `upshot://editor/recording-export-audio`: export audio with current editor settings.
- `upshot://editor/recording-cancel-export`: cancel the movie export.

## Screenshot Editor Controls

The annotation editor registers its existing save, export, close, sharing, and undo callbacks with `AutomationEditorActions.register`. The frontmost visible registered screenshot editor receives the action. Closed windows remove their registration.

- `upshot://editor/save`: invoke Save.
- `upshot://editor/save-copy`: invoke Save a Copy As.
- `upshot://editor/done`: invoke Save and Close.
- `upshot://editor/share`: invoke the registered sharing callback.
- `upshot://editor/undo`: invoke Undo.
- `upshot://editor/redo`: invoke Redo.

## Selection and Desktop Actions

- `upshot://selection/toggle-crosshair`: toggle the selector crosshair preference.
- `upshot://selection/toggle-magnifier`: toggle the selector magnifier preference.
- `upshot://desktop/toggle-icons`: hide or restore desktop icons through wallpaper windows. Manual hiding remains active until toggled off.

## Annotation Actions

The frontmost visible registered screenshot editor receives these actions. An editor that is busy or cropping rejects the action. Image transforms and color processing complete before their command returns. Combining without `path` acknowledges the image chooser; choosing the image continues asynchronously.

- `upshot://editor/highlighter`: select Highlighter with recognized-text snapping.
- `upshot://editor/measure`: select Measure.
- `upshot://editor/text-plain`: select Plain text style.
- `upshot://editor/text-label`: select Label text style.
- `upshot://editor/text-callout`: select Callout text style.
- `upshot://editor/redaction-style?value=box`: set `blur`, `pixelate`, `box`, `disc`, `motionHorizontal`, `motionVertical`, `zoom`, or `hexagonal`. Omitting `value` cycles to the next style.
- `upshot://editor/rotate-clockwise`: rotate the image and annotations clockwise.
- `upshot://editor/rotate-counterclockwise`: rotate the image and annotations counterclockwise.
- `upshot://editor/flip-horizontal`: reflect the image and annotations horizontally.
- `upshot://editor/flip-vertical`: reflect the image and annotations vertically.
- `upshot://editor/combine-side-by-side?path=...`: combine another image to the right. Omitting `path` opens an image chooser.
- `upshot://editor/combine-stacked?path=...`: combine another image below. Omitting `path` opens an image chooser.
- `upshot://editor/drawing-smoothing?value=0.62`: set smoothing from zero through one. Omitting `value` toggles between zero and 0.62.
- `upshot://editor/object-shadows?value=true`: set new-object and selected-object shadows. Omitting `value` toggles the current setting.
- `upshot://editor/expand-canvas?value=true`: set automatic canvas expansion. Omitting `value` toggles the preference.
- `upshot://editor/always-on-top?value=true`: set editor window level. Omitting `value` toggles the preference.
- `upshot://editor/color-adjustments?value=...`: set a JSON object containing `exposure`, `contrast`, `saturation`, and `temperature`. Accepted ranges are -3–3, 0–2, 0–2, and -100–100, respectively. All four fields are required. Omitting `value` resets the adjustments.
- `upshot://editor/watermark?value=...&path=...`: patch watermark settings with an optional JSON `value` and optional image `path`. Supported JSON fields are `text`, `opacity` from zero through one, `position`, `rotationDegrees` from -360 through 360, `fontSize` from 1 through 1000, `imageWidth` from 0.02 through 0.9, and `isEnabled`. Positions are `tiled`, `topLeft`, `top`, `topRight`, `left`, `center`, `right`, `bottomLeft`, `bottom`, and `bottomRight`. Text clears the prior image; an image path takes precedence over text. A patch enables the watermark unless `isEnabled` is false. An image path enables the watermark. Omitting both parameters toggles the stored watermark.

JSON parameter values require URL percent encoding. The CLI accepts the same values through `--value` without URL encoding. No parameter changes the existing global shortcut assignment; every new action starts unassigned.
