---
review_status: unreviewed
approval_status: not_approved
---

# Command-Line Tool

The app executable provides `--cli`. A symlink named `upshot` selects CLI mode automatically. CLI mode exits before SwiftUI starts and never launches the app. Upshot must already be running with Allow AI agents enabled in Settings → MCP.

## Installation

For the release app installed in Applications:

```sh
mkdir -p "$HOME/.local/bin"
ln -s /Applications/Upshot.app/Contents/MacOS/Upshot "$HOME/.local/bin/upshot"
```

Ensure the local bin directory is on `PATH`. The symlink follows app updates at the same installation path. If an existing `upshot` file occupies the destination, inspect that file before replacing it.

Without a symlink, invoke the app executable with `--cli` followed by the same arguments. For a development build, use the executable inside the Upshot Dev app and pass `--cli --dev`.

## Commands

```sh
upshot --help
upshot actions
upshot capture fullscreen --output "$HOME/Desktop/capture.png"
upshot capture window --output "$HOME/Desktop/window.png"
upshot capture area --output "$HOME/Desktop/area.png"
upshot capture text --output "$HOME/Desktop/captured-text.txt"
upshot capture area-copy
upshot capture area-save
upshot capture area-upload --json
upshot capture self-timer --delay 5
upshot recording start
upshot recording pause
upshot recording resume
upshot recording stop
upshot editor open --path "$HOME/Desktop/capture.png"
upshot library open
upshot settings screenshots
```

The commands and actions correspond directly to the routes in [URL Scheme](url-scheme.md). The command is the first route component; the action is the second component. `upshot actions` reads the running app's registry, so newly integrated cases appear automatically.

## Options

- `--output FILE`: write the completed capture to a new destination. Screenshot paths require `.png`; text captures write UTF-8. Relative paths resolve against the CLI's current directory. The parent directory must exist. Existing files are preserved.
- `--path FILE`: choose an image, video, recording project, image to combine, or watermark image for the corresponding command. Relative paths resolve against the CLI's current directory.
- `--value VALUE`: supply an editor style, numeric value, Boolean, or JSON settings object. Shell-quote JSON objects to preserve their punctuation.
- `--delay SECONDS`: set the self-timer delay for one self-timer capture. The accepted range is 1–3600 seconds; the default is five seconds.
- `--dev`: use the existing `agent-dev.sock` socket.
- `--socket FILE`: use a specified Unix socket. This overrides earlier socket options.
- `--timeout SECONDS`: wait for a response for this duration. The default is 300 seconds. A timed-out request may still finish in the app. Check the app before repeating a capture or recording command.
- `--json`: print the structured result instead of its primary value.

## Results

Successful screenshot commands print a file path. Capture Text prints recognized text unless `--output` supplies a destination, in which case the command prints the destination path. Capture Area and Save prints the saved export path. Capture Area and Upload returns a history path and an upload URL in JSON. Other actions print `accepted` once the app accepts the operation.

Fullscreen, window, and area captures use the existing capture coordinator and preserve configured after-capture actions. The named copy, save, and upload commands run only the named output action and preserve the capture in history.

Recording start, stop, restart, and discard acknowledge acceptance. Recording preparation and finalization continue in the app. Stop does not return an exported movie path. Recording export remains available through the existing MCP tools.

A successful command exits with status 0. Invalid arguments, app errors, cancellation, unavailable sockets, and disconnected sockets exit with status 1 and print the error to standard error. CLI commands never retry a request automatically.

Capture Previous Area uses the coordinator's saved screenshot rectangle and normal output processing. Capture All-In-One opens the shared selector; its Recording and Scrolling modes return acceptance without a screenshot. An output destination requires a screenshot.

## Socket Protocol

The CLI connects to the existing agent socket and sends one newline-delimited JSON-RPC request. The app retains its existing same-user socket check and agent-server preference.

```json
{"jsonrpc":"2.0","id":1,"method":"upshot/perform","params":{"route":"capture/area","parameters":{"output":"/tmp/capture.png"}}}
```

`upshot/actions` returns the route and title of every action. `upshot/perform` returns an action result or JSON-RPC error code `-32001`. The existing MCP methods retain their behavior.

The release socket is in `~/Library/Application Support/Upshot/agent.sock`. The Dev socket is in the same directory with the name `agent-dev.sock`.

## Verification

Run `upshot --help` without the app to verify CLI dispatch. With the app running, run `upshot actions --json` and compare routes against the shortcut catalog. Capture an area to a new PNG destination and inspect the file, dimensions, and contents. Repeat with the same destination and confirm the existing file remains unchanged. Cancel an area selection and confirm a nonzero exit status. Record briefly, pause, resume, and stop; verify the resulting recording project in the Library.

Successful captures log `Automation capture completed action=<route> path=<path>`. Every successful action logs `Automation action completed action=<route>`. Failed app actions log `Automation action failed action=<route> error=<reason>`.

Library selection commands include `library preview`, `library edit`, `library rename`, `library copy`, `library export`, `library reveal`, `library trash`, and `library refresh`. The current Library selection supplies the captures. Dialog-based commands open the existing dialog and retain its confirmation behavior.

Recording editor commands include `editor recording-save`, `editor recording-undo`, `editor recording-redo`, `editor recording-play`, `editor recording-pause`, `editor recording-export`, `editor recording-export-audio`, and `editor recording-cancel-export`. An optional `--path` chooses an already-open recording. Movie and audio exports continue asynchronously in the editor.

Screenshot editor commands `editor save`, `editor save-copy`, `editor done`, `editor share`, `editor undo`, and `editor redo` use the registered callbacks of the frontmost visible screenshot editor. The editor must be idle and outside cropping mode.

## Integrated Commands

Every command below also appears in `upshot actions` and the searchable shortcut catalog. Parameter semantics and all accepted values are in [URL Scheme](url-scheme.md).

```sh
upshot capture previous-area
upshot capture all-in-one
upshot capture smart-element
upshot selection toggle-crosshair
upshot selection toggle-magnifier
upshot desktop toggle-icons
upshot library history
upshot library restore-last
upshot library copy-text
upshot library detect-codes
upshot recording toggle-pen
upshot recording clear-pen
upshot editor recording-export-gif
upshot editor highlighter
upshot editor measure
upshot editor text-plain
upshot editor text-label
upshot editor text-callout
upshot editor redaction-style --value hexagonal
upshot editor rotate-clockwise
upshot editor rotate-counterclockwise
upshot editor flip-horizontal
upshot editor flip-vertical
upshot editor combine-side-by-side --path "$HOME/Pictures/second.png"
upshot editor combine-stacked --path "$HOME/Pictures/second.png"
upshot editor drawing-smoothing --value 0.62
upshot editor object-shadows --value true
upshot editor expand-canvas --value true
upshot editor always-on-top --value true
upshot editor color-adjustments --value '{"exposure":0,"contrast":1,"saturation":0.5,"temperature":0}'
upshot editor watermark --value '{"text":"Upshot","position":"bottomRight","opacity":0.5,"rotationDegrees":0}'
upshot editor watermark --path "$HOME/Pictures/watermark.png"
```

Live pen commands require an active, unpaused recording. GIF export requires an open recording editor. Library recognition commands require one selected screenshot. Annotation actions require an idle screenshot editor. Combining without `--path` opens the image chooser. Watermark, smoothing, shadows, canvas expansion, and always-on-top actions support parameterless toggling as documented in URL Scheme.

All screenshot-producing commands apply screenshot output preferences before history import. Capture Text bypasses screenshot output processing. Failed processing retains the raw capture and reports Capture failed.
