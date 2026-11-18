
import Foundation

enum AgentClock: String {
    case source
    case edited
}

struct AgentArguments {
    let raw: JSONValue

    func string(_ key: String) throws -> String {
        guard let value = raw[key]?.stringValue, !value.isEmpty else {
            throw AgentToolError.message("Missing required string argument \"\(key)\".")
        }
        return value
    }

    func optionalString(_ key: String) -> String? {
        raw[key]?.stringValue
    }

    func double(_ key: String) throws -> Double {
        guard let value = raw[key]?.doubleValue, value.isFinite else {
            throw AgentToolError.message("Missing required number argument \"\(key)\".")
        }
        return value
    }

    func optionalDouble(_ key: String) -> Double? {
        raw[key]?.doubleValue
    }

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        raw[key]?.boolValue ?? defaultValue
    }

    func array(_ key: String) throws -> [JSONValue] {
        guard let value = raw[key]?.arrayValue else {
            throw AgentToolError.message("Missing required array argument \"\(key)\".")
        }
        return value
    }

    func clock() throws -> AgentClock {
        guard let raw = raw["clock"]?.stringValue else {
            throw AgentToolError.message("Pass \"clock\": \"source\" or \"edited\" to say which timeline the times are on.")
        }
        guard let clock = AgentClock(rawValue: raw) else {
            throw AgentToolError.message("\"clock\" must be \"source\" or \"edited\", not \"\(raw)\".")
        }
        return clock
    }

    func recording() throws -> String {
        try string("recording")
    }
}

@MainActor
enum AgentTools {
    static let instructions = """
    Upshot is a local macOS screen recorder with a non-destructive video editor (Studio). \
    These tools read and edit Upshot recordings and export the result.

    Workflow: list_recordings → get_recording (timeline, clips, every overlay) → get_transcript and \
    get_input_events to find moments → edit → get_frame to look at the picture → export_video.

    Two clocks. "source" time is seconds into the raw recording and never changes. "edited" time is \
    seconds into the cut movie, after cuts and speed changes. Every tool that takes a time asks which \
    clock it is on, and outputs give both where they exist. Zooms, text, redactions, camera layouts and \
    captions are stored on the source clock, so they stay attached to their footage when you cut; \
    added audio clips are on the edited clock.

    Coordinates are normalized 0...1 with a top-left origin. Points encode as [x, y] and rects as \
    [[x, y], [width, height]].

    Edits are saved to the project's draft right away and each one is a single undo step. If the \
    recording is open in Studio the user sees the change live and can undo it there. Call \
    save_project when the user wants the edit committed. Call get_editing_guide for every allowed \
    enum value (fonts, animations, layouts, export formats, backgrounds).
    """

    private static let updateProjectPatchSchema: JSONValue = [
        "type": "object",
        "description": "Merge patch against get_recording's document. subtitleAppearance stores caption styling. Selecting preset copies its colors, opacity, radius, and animation before applying explicit overrides. Existing subtitleVerticalPosition, subtitleFontScale, and subtitleWordHighlight remain accepted.",
        "properties": [
            "exportAspect": ["type": "string", "enum": enumValues(ExportAspectPreset.self)],
            "exportCustomAspectWidth": ["type": "integer", "minimum": 128, "maximum": 7680],
            "exportCustomAspectHeight": ["type": "integer", "minimum": 128, "maximum": 7680],
            "clickEffect": ["type": "string", "enum": enumValues(RecordingClickEffect.self)],
            "clickEffectColor": ["type": "string", "pattern": "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"],
            "clickEffectScale": ["type": "number", "minimum": 0.5, "maximum": 2],
            "clickEffectOpacity": ["type": "number", "minimum": 0, "maximum": 1],
            "clickEffectDuration": ["type": "number", "minimum": 0.12, "maximum": 1.2, "description": "Click effect duration in seconds."],
            "style": [
                "type": "object",
                "properties": [
                    "cameraPictureCrop": [
                        "type": ["array", "null"],
                        "description": "Normalized camera source crop [[x, y], [width, height]] from the top-left, minimum side 0.08. Null restores the full picture.",
                        "minItems": 2,
                        "maxItems": 2,
                        "items": ["type": "array", "minItems": 2, "maxItems": 2, "items": ["type": "number", "minimum": 0, "maximum": 1]],
                    ],
                    "cameraLayout": [
                        "type": "object",
                        "properties": [
                            "positionPreset": ["type": "string", "enum": enumValues(RecordingCameraLayout.PositionPreset.self)],
                            "positionX": ["type": "number", "minimum": 0, "maximum": 1],
                            "positionY": ["type": "number", "minimum": 0, "maximum": 1],
                            "shape": ["type": "string", "enum": enumValues(RecordingCameraLayout.Shape.self)],
                            "width": ["type": ["number", "null"], "minimum": 0.1, "maximum": 1],
                            "height": ["type": ["number", "null"], "minimum": 0.1, "maximum": 1]
                        ]
                    ],
                    "cameraPreviewFrame": ["type": "string", "enum": ["legacy", "standard", "softBlur"]],
                    "cameraZoomResponse": ["type": "string", "enum": ["progress", "magnification"]],
                    "cameraShrinksDuringZoom": ["type": "boolean"],
                    "cameraZoomShrinkAmount": ["type": "number", "minimum": 0.05, "maximum": 0.7],
                    "backgroundBlur": ["type": ["number", "null"], "minimum": 0, "maximum": 8, "multipleOf": 0.25, "description": "Wallpaper blur in pixels at a 640-pixel canvas width. Null restores zero."],
                    "paddingSides": [
                        "type": ["object", "null"],
                        "description": "Per-side percentages scaled by 0.2. Null restores legacy uniform padding. Linked values use top for every side.",
                        "properties": [
                            "top": ["type": "number", "minimum": 0, "maximum": 250],
                            "bottom": ["type": "number", "minimum": 0, "maximum": 250],
                            "left": ["type": "number", "minimum": 0, "maximum": 100],
                            "right": ["type": "number", "minimum": 0, "maximum": 100],
                            "linked": ["type": "boolean"]
                        ]
                    ],
                    "authoredGradient": [
                        "type": ["object", "null"],
                        "description": "Selects a custom linear gradient. Null clears the authored angle metadata and retains the stored background.",
                        "properties": [
                            "angle": ["type": "integer", "minimum": 0, "maximum": 360],
                            "colors": ["type": "array", "minItems": 2, "maxItems": 5, "items": ["type": "string", "pattern": "^#[0-9a-fA-F]{6}$"]]
                        ]
                    ],
                    "shadow": ["type": "number", "minimum": 0, "maximum": 1, "multipleOf": 0.01],
                    "usesLayeredShadow": ["type": "boolean", "description": "Uses the two-layer 640-pixel reference profile. Editing shadow selects this profile unless explicitly overridden."],
                    "cursorSmoothing": ["type": ["number", "null"], "minimum": 0, "maximum": 2, "description": "Null preserves the existing spring. Zero disables glide smoothing."],
                    "cursorSpringStiffnessMultiplier": ["type": "number", "minimum": 0.25, "maximum": 3],
                    "cursorSpringDampingMultiplier": ["type": "number", "minimum": 0.25, "maximum": 3],
                    "cursorSpringMassMultiplier": ["type": "number", "minimum": 0.25, "maximum": 3],
                    "cursorClickBounce": ["type": ["number", "null"], "minimum": 0, "maximum": 5, "description": "Null preserves the existing click pulse."],
                    "cursorClickBounceDuration": ["type": "number", "minimum": 0.06, "maximum": 0.5, "description": "Click bounce duration in seconds."]
                ]
            ],
            "subtitleAppearance": [
                "type": "object",
                "properties": [
                    "preset": ["type": "string", "enum": ["upshot", "reveal", "serif"]],
                    "fontSize": ["type": "number", "minimum": 16, "maximum": 72],
                    "maximumRows": ["type": "integer", "minimum": 1, "maximum": 4],
                    "bottomOffset": ["type": "number", "minimum": 0, "maximum": 30],
                    "maximumWidth": ["type": "number", "minimum": 40, "maximum": 95],
                    "boxRadius": ["type": "number", "minimum": 0, "maximum": 40],
                    "backgroundOpacity": ["type": "number", "minimum": 0, "maximum": 1],
                    "animation": ["type": "string", "enum": ["none", "fade", "rise", "pop"]],
                    "textColor": ["type": "string", "description": "Hexadecimal RGB or RGBA color."],
                    "inactiveTextColor": ["type": "string"],
                    "revealsWords": ["type": "boolean"],
                    "highlightsSpokenWord": ["type": "boolean"],
                    "highlightFill": ["type": "string"],
                    "highlightTextColor": ["type": "string"],
                    "verticalPosition": ["type": "number", "minimum": 0.1, "maximum": 0.95],
                    "fontScale": ["type": "number", "minimum": 0.6, "maximum": 1.8]
                ]
            ]
        ]
    ]

    private static let updateProjectAppearanceSchema: JSONValue = [
        "type": "object",
        "description": "Merge patch against get_recording's exportAppearance. All zoom durations are seconds. Null zoomMotion preserves legacy animation.",
        "properties": [
            "zoomMotion": [
                "type": ["object", "null"],
                "properties": [
                    "zoomInDuration": ["type": "number", "minimum": 0.06, "maximum": 4],
                    "zoomOutDuration": ["type": "number", "minimum": 0.06, "maximum": 4],
                    "connectZooms": ["type": "boolean"],
                    "connectedZoomGap": ["type": "number", "minimum": 0, "maximum": 5, "description": "Connection eligibility is capped at 1.5 seconds."],
                    "connectedZoomDuration": ["type": "number", "minimum": 0.06, "maximum": 4]
                ]
            ]
        ]
    ]

    static var definitions: [JSONValue] {
        [
            tool(
                "list_recordings",
                title: "List recordings",
                description: "Lists Upshot recordings, most recently used first, with their ids, names, durations and sizes. Use the id with every other tool.",
                properties: [
                    "query": ["type": "string", "description": "Only recordings whose name contains this text (case-insensitive)."],
                    "limit": ["type": "integer", "description": "Most to return. Defaults to 20."],
                ],
                readOnly: true
            ),
            tool(
                "get_recording",
                title: "Get recording",
                description: "The whole edit of one recording: source and edited durations, the clip list (source range, speed, edited range), every zoom, text, redaction, camera layout, image and audio clip with its source and edited times, the style, and the export settings. The `document` field is the editable project; update_project patches it.",
                properties: ["recording": recordingProperty],
                required: ["recording"],
                readOnly: true
            ),
            tool(
                "get_transcript",
                title: "Get transcript",
                description: "Word-level transcript with source times, edited times (blank when the word has been cut), and filler-word flags, plus the caption cues. Word indices are what edit_transcript's cut_words takes. Set transcribe_if_missing to run on-device speech recognition first when the recording has none (can take a minute).",
                properties: [
                    "recording": recordingProperty,
                    "transcribe_if_missing": ["type": "boolean", "description": "Transcribe the recording if it has no transcript yet. Defaults to false."],
                    "language": ["type": "string", "description": "BCP-47 language identifier for on-device transcription, such as en-US. An empty string uses the system default. Omit to use the selected transcription language. Applies only when transcribe_if_missing generates a transcript."],
                    "include_cut_words": ["type": "boolean", "description": "Include words already cut from the edit. Defaults to true."],
                ],
                required: ["recording"],
                readOnly: false
            ),
            tool(
                "get_input_events",
                title: "Get input events",
                description: "What the user did while recording: mouse clicks (with normalized position), keyboard shortcuts, and optionally the cursor path. Times are given on both clocks. Good for finding where to zoom, what to cut, or what a moment shows.",
                properties: [
                    "recording": recordingProperty,
                    "start": ["type": "number", "description": "Start of the window, in seconds on `clock`. Defaults to the beginning."],
                    "end": ["type": "number", "description": "End of the window, in seconds on `clock`. Defaults to the end."],
                    "clock": clockProperty,
                    "include_cursor": ["type": "boolean", "description": "Include cursor positions sampled at cursor_hz. Defaults to false."],
                    "cursor_hz": ["type": "number", "description": "Cursor samples per second when include_cursor is true. Defaults to 4."],
                ],
                required: ["recording", "clock"],
                readOnly: true
            ),
            tool(
                "get_frame",
                title: "Get frame",
                description: "A JPEG of the raw recorded screen at a moment, so you can see what is on screen. This is the unstyled source picture (no background, zoom or overlays), which is the same space redaction rects and zoom points use.",
                properties: [
                    "recording": recordingProperty,
                    "time": ["type": "number", "description": "Seconds on `clock`."],
                    "clock": clockProperty,
                    "max_size": ["type": "integer", "description": "Longest side in pixels. Defaults to 1280."],
                ],
                required: ["recording", "time", "clock"],
                readOnly: true
            ),
            tool(
                "cut",
                title: "Cut ranges",
                description: "Removes time ranges from the edited movie. Non-destructive: the footage stays in the source and can be restored with undo or by patching `clips`. Captions overlapping a cut lose the cut words.",
                properties: [
                    "recording": recordingProperty,
                    "ranges": [
                        "type": "array",
                        "description": "Ranges to remove, each {start, end} in seconds on `clock`.",
                        "items": rangeSchema,
                    ],
                    "clock": clockProperty,
                ],
                required: ["recording", "ranges", "clock"]
            ),
            tool(
                "set_speed",
                title: "Set speed",
                description: "Changes a range's playback speed from 0.25 to 30×, splitting clips at its edges. Audio stays in sync with the picture. Use 1 to return a range to normal speed.",
                properties: [
                    "recording": recordingProperty,
                    "start": ["type": "number", "description": "Seconds on `clock`."],
                    "end": ["type": "number", "description": "Seconds on `clock`."],
                    "clock": clockProperty,
                    "speed": ["type": "number", "minimum": 0.25, "maximum": 30, "description": "Playback rate, 0.25...30. Values below 1 produce slow motion."],
                ],
                required: ["recording", "start", "end", "clock", "speed"]
            ),
            tool(
                "set_clip_muted",
                title: "Mute clip",
                description: "Mutes or unmutes one clip's recorded audio while retaining its picture. Imported audio clips and replacement audio remain audible.",
                properties: [
                    "recording": recordingProperty,
                    "clip_id": ["type": "string", "description": "Clip id from get_recording."],
                    "muted": ["type": "boolean", "description": "True silences recorded audio; false restores it."],
                ],
                required: ["recording", "clip_id", "muted"]
            ),
            tool(
                "edit_transcript",
                title: "Edit by transcript",
                description: "Transcript-driven cuts. remove_filler_words cuts \"um\", \"uh\" and similar; trim_silences shortens long pauses in the narration; cut_words cuts the footage under words from_index through to_index (inclusive, indices from get_transcript). Needs a transcript.",
                properties: [
                    "recording": recordingProperty,
                    "action": ["type": "string", "enum": ["remove_filler_words", "trim_silences", "cut_words"]],
                    "from_index": ["type": "integer", "description": "First word to cut (cut_words)."],
                    "to_index": ["type": "integer", "description": "Last word to cut, inclusive (cut_words)."],
                ],
                required: ["recording", "action"]
            ),
            tool(
                "add_items",
                title: "Add items",
                description: "Adds zooms, text, arrows, redactions (blur/pixelate/color fill), camera layout changes, or captions. Each item is a partial object: give start and end (on `clock`) plus any fields you want to set; the rest take defaults. Field names match get_recording's document. Returns the created items with their ids. Images and audio are added with add_media.",
                properties: [
                    "recording": recordingProperty,
                    "kind": ["type": "string", "enum": ["zoom", "text", "redaction", "arrow", "camera_layout", "caption"]],
                    "clock": clockProperty,
                    "items": ["type": "array", "items": ["type": "object"], "description": itemFieldsDescription],
                ],
                required: ["recording", "kind", "clock", "items"]
            ),
            tool(
                "update_items",
                title: "Update items",
                description: "Changes existing items by id. Each entry is {id, ...fields to change}; fields you leave out keep their values (merge patch). Times you give are on `clock`.",
                properties: [
                    "recording": recordingProperty,
                    "kind": itemKindProperty,
                    "clock": clockProperty,
                    "items": ["type": "array", "items": ["type": "object"], "description": itemFieldsDescription],
                ],
                required: ["recording", "kind", "clock", "items"]
            ),
            tool(
                "remove_items",
                title: "Remove items",
                description: "Removes items by id.",
                properties: [
                    "recording": recordingProperty,
                    "kind": itemKindProperty,
                    "ids": ["type": "array", "items": ["type": "string"]],
                ],
                required: ["recording", "kind", "ids"],
                destructive: true
            ),
            tool(
                "add_media",
                title: "Add media",
                description: "Copies an image, GIF, or audio file into the project and places it at a time. Images become overlays (move them with update_items kind \"image\"); audio becomes a clip under the video.",
                properties: [
                    "recording": recordingProperty,
                    "path": ["type": "string", "description": "Absolute path to the file."],
                    "time": ["type": "number", "description": "Where it starts, seconds on `clock`."],
                    "clock": clockProperty,
                ],
                required: ["recording", "path", "time", "clock"]
            ),
            tool(
                "set_camera_source",
                title: "Set camera source",
                description: "Copies a camera video into the project, enables the camera, and loops the video from source time zero. Omit path to remove the project camera source. The recorded sidecar remains on disk.",
                properties: [
                    "recording": recordingProperty,
                    "path": ["type": "string", "description": "Absolute path to a camera video. Omit to remove the camera source."],
                ],
                required: ["recording"]
            ),
            tool(
                "update_project",
                title: "Update project",
                description: "Applies a JSON merge patch (RFC 7386) to the project document from get_recording: objects merge, arrays replace, null removes. Use it for style (background, padding, cornerRadius, shadow, cursor, camera), toggles (zoomEnabled, showsSubtitles, showsKeystrokes, showsClickEffects, showsSpeedBadge), subtitle look, exportAspect/exportAspectMode, videoCropRect, audioVolume, exportSettings, or the `clips` list itself (source ranges with speeds, in order). Rejected if the result is not a valid project.",
                properties: [
                    "recording": recordingProperty,
                    "patch": updateProjectPatchSchema,
                    "appearance": updateProjectAppearanceSchema,
                    "motionPreset": ["type": "string", "enum": enumValues(RecordingMotionPreset.self), "description": "Apply Focused or Cinematic zoom timing, cursor size, smoothing, spring multipliers, and click bounce."],
                ],
                required: ["recording", "patch"]
            ),
            tool(
                "undo",
                title: "Undo",
                description: "Undoes the last edit (yours or the user's in Studio).",
                properties: [
                    "recording": recordingProperty,
                    "steps": ["type": "integer", "description": "How many edits to undo. Defaults to 1."],
                ],
                required: ["recording"]
            ),
            tool(
                "redo",
                title: "Redo",
                description: "Redoes the last undone edit.",
                properties: [
                    "recording": recordingProperty,
                    "steps": ["type": "integer", "description": "How many edits to redo. Defaults to 1."],
                ],
                required: ["recording"]
            ),
            tool(
                "save_project",
                title: "Save project",
                description: "Commits the current edit as the project's saved state (like ⌘S in Studio). Edits are already autosaved to a draft; saving is what the user sees as \"saved\".",
                properties: ["recording": recordingProperty],
                required: ["recording"]
            ),
            tool(
                "open_in_studio",
                title: "Open in Studio",
                description: "Opens the recording in a Upshot Studio window so the user can watch and review the edit.",
                properties: ["recording": recordingProperty],
                required: ["recording"]
            ),
            tool(
                "export_video",
                title: "Export video",
                description: "Renders the edited video with everything applied and saves it. By default it goes to the user's Upshot export folder; output_path moves it somewhere specific. Waits for the render and reports progress unless wait is false (then poll export_status).",
                properties: [
                    "recording": recordingProperty,
                    "output_path": ["type": "string", "description": "Absolute file path to move the finished video to. Its extension should match the container."],
                    "appearance": ["type": "object", "description": "Merge patch for export appearance. zoomAnimationStyle: Smooth or Dynamic. keystrokes: {size: Small|Medium|Large, style: Dark|Light, position: topLeft|topCenter|topRight|middleLeft|middleCenter|middleRight|bottomLeft|bottomCenter|bottomRight, filter: Command Keys Only|All Keys}. Typed keys are hidden by default and exist only if capture was explicitly enabled before recording. shot: Flat, Tilt Left, Tilt Right, Tilt Up, or Orbit (export only). Saved per project. Zoom animation style also applies to the Studio preview."],
                    "options": [
                        "type": "object",
                        "description": "Merge patch for additional export options. format: Video or GIF; gifFrameRate: 10, 15, 20, 25, or 30; gifQuality: Low, Medium, or High; optimizesGIF, scalesRetinaToOne, monoAudio, separateAudioTracks: booleans. motionBlurLevel: Off, Low, Medium, or High. GIF contains no audio. Saved per project.",
                        "properties": [
                            "gifSize": ["type": "string", "enum": enumValues(RecordingGIFSize.self)],
                            "gifLoops": ["type": "boolean"],
                        ]
                    ],
                    "settings": [
                        "type": "object",
                        "description": "Merge patch for the export settings: quality, speed, codec, resolution, customWidth, customHeight, encodingMode, container, frameRate, motionBlurEnabled, removeAudio. Fixed resolution tiers set the longest edge and may upscale. Custom dimensions must be even, 2 through 8192. See get_editing_guide for values. Saved into the project.",
                        "properties": [
                            "resolution": ["type": "string", "enum": enumValues(VideoCompressionResolution.self)],
                            "customWidth": ["type": "integer", "minimum": 2, "maximum": 8192, "multipleOf": 2],
                            "customHeight": ["type": "integer", "minimum": 2, "maximum": 8192, "multipleOf": 2],
                            "encodingMode": ["type": "string", "enum": enumValues(VideoExportEncodingMode.self)],
                            "frameRate": ["type": "string", "enum": enumValues(VideoExportFrameRate.self)],
                        ]
                    ],
                    "wait": ["type": "boolean", "description": "Wait for the export to finish. Defaults to true."],
                ],
                required: ["recording"]
            ),
            tool(
                "export_audio",
                title: "Export audio",
                description: "Writes the edited soundtrack on its own (cuts and speed applied).",
                properties: [
                    "recording": recordingProperty,
                    "output_path": ["type": "string", "description": "Absolute file path to move the finished audio to."],
                    "format": ["type": "string", "description": "Audio format; see get_editing_guide. Defaults to the project's."],
                    "mono": ["type": "boolean", "description": "Export one audio channel. Defaults to the project export option."],
                    "wait": ["type": "boolean", "description": "Wait for the export to finish. Defaults to true."],
                ],
                required: ["recording"]
            ),
            tool(
                "export_status",
                title: "Export status",
                description: "Progress or result of the latest video and audio export for a recording.",
                properties: ["recording": recordingProperty],
                required: ["recording"],
                readOnly: true
            ),
            tool(
                "get_editing_guide",
                title: "Editing guide",
                description: "Reference for editing: every allowed enum value (zoom anchors, fonts, text animations, redaction styles, camera layouts, keystroke placements, export aspect, quality, codec, container, frame rate, audio formats, cursor styles), the item field lists, and the background presets.",
                properties: [:],
                readOnly: true
            ),
        ]
    }

    static func call(_ name: String, arguments raw: JSONValue, progress: @escaping AgentProgress) async throws -> [JSONValue] {
        let arguments = AgentArguments(raw: raw)
        switch name {
        case "list_recordings": return try listRecordings(arguments)
        case "get_recording": return try await getRecording(arguments)
        case "get_transcript": return try await getTranscript(arguments, progress: progress)
        case "get_input_events": return try await getInputEvents(arguments)
        case "get_frame": return try await getFrame(arguments)
        case "cut": return try await cut(arguments)
        case "set_speed": return try await setSpeed(arguments)
        case "set_clip_muted": return try await setClipMuted(arguments)
        case "edit_transcript": return try await editTranscript(arguments)
        case "add_items": return try await addItems(arguments)
        case "update_items": return try await updateItems(arguments)
        case "remove_items": return try await removeItems(arguments)
        case "add_media": return try await addMedia(arguments)
        case "set_camera_source": return try await setCameraSource(arguments)
        case "update_project": return try await updateProject(arguments)
        case "undo": return try await undoRedo(arguments, redo: false)
        case "redo": return try await undoRedo(arguments, redo: true)
        case "save_project": return try await saveProject(arguments)
        case "open_in_studio": return try openInStudio(arguments)
        case "export_video": return try await exportVideo(arguments, progress: progress)
        case "export_audio": return try await exportAudio(arguments, progress: progress)
        case "export_status": return try await exportStatus(arguments)
        case "get_editing_guide": return [text(AgentEditingGuide.text + "\n" + RecordingExportAgentGuide.text)]
        default: throw AgentToolError.message("Unknown tool \"\(name)\".")
        }
    }


    static let recordingProperty: JSONValue = [
        "type": "string",
        "description": "Recording id from list_recordings (an absolute package path also works).",
    ]

    static let clockProperty: JSONValue = [
        "type": "string",
        "enum": ["source", "edited"],
        "description": "Timeline the times are on: \"source\" = seconds into the raw recording, \"edited\" = seconds into the cut movie.",
    ]

    static let itemKindProperty: JSONValue = [
        "type": "string",
        "enum": ["zoom", "text", "redaction", "arrow", "camera_layout", "caption", "image", "audio"],
    ]

    static let rangeSchema: JSONValue = [
        "type": "object",
        "properties": ["start": ["type": "number"], "end": ["type": "number"]],
        "required": ["start", "end"],
    ]

    static let itemFieldsDescription: JSONValue = """
    zoom: start, end, zoom (continuous magnification 1-5; presets 1.25, 1.5, 1.8, 2.2, 3.5, 5; new items default to 1.8), anchorMode, pinnedPoint [x,y] (framed when anchorMode is \"pinnedAnchor\"), isEnabled. \
    text: start, end, text, coordinateSpace (canvas|recording, default canvas), center [x,y], fontSize (fraction of coordinate-space height, 0.02-0.3), font, color {red,green,blue,alpha 0-1}, isBold, hasBackground, backgroundColor, animationIn, animationOut. \
    redaction: start, end, rect [[x,y],[w,h]] in the recorded picture, style (pixelate|blur), fillColor (null for no fill, or {red,green,blue,alpha 0-1}; opaque skips filtering, translucent tints filtered pixels), amount 0-1, cornerRadius, fadeIn, fadeOut. \
    arrow: start, end, rect [[x,y],[w,h]], coordinateSpace (canvas|recording, default recording), direction (up|down|left|right|up-right|up-left|down-right|down-left), color {red,green,blue,alpha 0-1}, strokeWidth (integer 1-6). \
    camera_layout: start, end, layout (see get_editing_guide). \
    caption: start, end, text. \
    image: start, end, coordinateSpace (canvas|recording, default canvas), center [x,y], width (fraction of coordinate-space width), rotation (degrees), opacity, cornerRadius, shadow, shadowScale (default 1; converted automatically when coordinateSpace changes), fadeIn, fadeOut. \
    audio: start (edited clock), trimStart, trimEnd, volume 0-1, fadeIn, fadeOut.
    """

    private static func enumValues<Value: RawRepresentable & CaseIterable>(_ type: Value.Type) -> JSONValue where Value.RawValue == String {
        .array(Value.allCases.map { .string($0.rawValue) })
    }

    private static func tool(
        _ name: String,
        title: String,
        description: String,
        properties: [String: JSONValue],
        required: [String] = [],
        readOnly: Bool = false,
        destructive: Bool = false
    ) -> JSONValue {
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": .object(schema),
            "annotations": [
                "title": .string(title),
                "readOnlyHint": .bool(readOnly),
                "destructiveHint": .bool(destructive),
                "idempotentHint": .bool(readOnly),
                "openWorldHint": false,
            ],
        ]
    }


    static func text(_ string: String) -> JSONValue {
        ["type": "text", "text": .string(string)]
    }

    static func json(_ value: JSONValue) -> JSONValue {
        text(value.compactString)
    }

    static func image(_ data: Data, mimeType: String) -> JSONValue {
        ["type": "image", "data": .string(data.base64EncodedString()), "mimeType": .string(mimeType)]
    }
}
