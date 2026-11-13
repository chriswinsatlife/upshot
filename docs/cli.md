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
- `--path FILE`: open an image, video, or recording project in its editor. Relative paths resolve against the CLI's current directory.
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

Capture Previous Area has a registry entry in phase one. The area-selection integration must install `AutomationActions.capturePreviousArea` before that command can capture a previous selection.

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
