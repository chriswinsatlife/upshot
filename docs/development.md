---
review_status: unreviewed
approval_status: not_approved
---

# Development

## Build

Upshot builds with `xcodebuild` and the Xcode 26.4 toolchain. The deployment target is macOS 26.0, the bundle identifier is `co.chrisyork.upshot`, and there is no test target.

```bash
xcodebuild build -project Upshot.xcodeproj -scheme Upshot -configuration Release -destination "platform=macOS"
```

The project also has an `Upshot Dev` scheme, which builds `Upshot Dev.app` with the bundle identifier `co.chrisyork.upshot.dev`, and an `Upshot Demo` scheme, which builds the regular app and launches it with `--demo-mode`. Use the `Upshot` scheme.

## Swift Concurrency

The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type is main-actor isolated unless it is marked `nonisolated`. It also sets `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`, so an import in one file does not make a module visible in another.

## Architecture

All source is in `Upshot/`, with the drawing engine in `Upshot/Engine/`.

- App entry: `UpshotApp.swift` creates the menu bar extra, Settings, and editor windows. The app runs as a menu bar app (`LSUIElement = YES`) and switches to a regular activation policy while Library, Settings, or editor windows are open.
- Shortcuts and automation: `CaptureHotkeys.swift` defines every user action in `CaptureHotkeyAction`, with its title, `upshot://` route, and optional default shortcut. The defaults are Option-1 fullscreen, Option-2 window, Option-3 area, Option-4 recording, Option-5 Capture Text, and Command-Shift-5 All-In-One. Command-Shift-5 is also the default macOS Screenshot toolbar shortcut, which can be turned off in System Settings, Keyboard, Keyboard Shortcuts, Screenshots. When Upshot cannot register a shortcut, the failure appears next to that shortcut in Settings. `AutomationActions.swift` executes actions for shortcuts, the menu, `AutomationURLRouter.swift`, and the `upshot` command-line tool in `AutomationCommandLine.swift`.
- Capture: `CaptureCoordinator.swift` drives every capture. Area, element, All-In-One, and scrolling captures use Upshot's own selector in `AreaCaptureSelection.swift`, which captures each display with ScreenCaptureKit before showing its overlay. `ScreenshotOutputService.swift` applies the optional screenshot output settings before a capture enters history.
- Quick Access: `CaptureShelf.swift`, `CaptureShelfPresenter.swift`, and `CaptureShelfCard.swift` show recent captures in a panel at the screen edge.
- Annotation: `AnnotationEditorModel.swift`, `AnnotationCanvas.swift`, and `AnnotationRenderer.swift`. Annotation positions and sizes are normalized to 0 through 1 relative to the source image; only the renderer and the canvas convert to pixels.
- Library: `CaptureLibraryView.swift` and `CaptureLibraryModel.swift`. `CaptureLibraryIndex.swift` and `CaptureLibraryAnalyzer.swift` analyze each capture on device with Vision text recognition, a feature print for Similar, and a category. The index lives in `Application Support/Upshot/Library Index`; raising `CaptureAnalysis.currentVersion` re-indexes every capture.
- Recording: `ScreenRecordingManager.swift` records, and the Studio editor in `RecordingStudioModel.swift` and `RecordingStudioExporter.swift` edits and exports.
- MCP server: `AgentRelay.swift`, `AgentServer.swift`, `AgentTools.swift`, and `AgentToolHandlers.swift` let MCP clients edit and export recordings. Clients launch the app executable with `--mcp`, which relays JSON-RPC to the socket `Application Support/Upshot/agent.sock`. The server is enabled in Settings, MCP.

## Conventions

- Apple frameworks plus two Swift packages: Sparkle for updates and DockProgress for Dock icon progress.
- State uses the Observation framework's `@Observable`.
- The App Sandbox is off and the hardened runtime is on; do not add sandbox entitlements.
- `MallocLargeCache=0` is set in `Info.plist` to limit retained heap memory.
