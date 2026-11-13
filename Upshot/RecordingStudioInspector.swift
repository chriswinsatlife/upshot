import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension ZoomAnchorMode {
    var inspectorTitle: String {
        switch self {
        case .pointerAnchor: "Pointer"
        case .smartAnchor: "Smart"
        case .pinnedAnchor: "Fixed"
        }
    }
}

private enum StudioTranscriptTab: Hashable {
    case captions
    case edit
}

enum StudioInspectorPage: String, CaseIterable, Identifiable, Hashable {
    case look
    case camera
    case zoom
    case cursor
    case keystrokes
    case captions
    case audio
    case clip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .look: "Look"
        case .camera: "Camera"
        case .zoom: "Zoom"
        case .cursor: "Cursor"
        case .keystrokes: "Keystrokes"
        case .captions: "Captions"
        case .audio: "Audio"
        case .clip: "Clip"
        }
    }

    var systemImage: String {
        switch self {
        case .look: "paintpalette"
        case .camera: "web.camera"
        case .zoom: "plus.magnifyingglass"
        case .cursor: "cursorarrow.rays"
        case .keystrokes: "command"
        case .captions: "captions.bubble"
        case .audio: "speaker.wave.2"
        case .clip: "film"
        }
    }

    static func available(for model: RecordingStudioModel) -> [StudioInspectorPage] {
        allCases.filter { page in
            switch page {
            case .look, .zoom, .audio, .clip: true
            case .camera: model.hasCameraVideo
            case .cursor: model.pointerIsSynthesized
            case .keystrokes: model.hasKeystrokes
            case .captions: model.canTranscribe || model.hasSubtitles
            }
        }
    }

    static var renderInitialPage: StudioInspectorPage {
        guard UpshotStorage.isRenderingStates else { return .look }
        let scenario = StateRenderer.scenario
        if scenario.contains("captions") || scenario.contains("transcript") { return .captions }
        return allCases.first { scenario.hasSuffix("-\($0.rawValue)") } ?? .look
    }

    static func highlightedPage(for model: RecordingStudioModel, current: StudioInspectorPage) -> StudioInspectorPage? {
        if model.selectedCue != nil { return .zoom }
        if model.selectedLayoutCue != nil { return .camera }
        if model.selectedAudioClip != nil { return .audio }
        if model.selectedText != nil || model.selectedRedaction != nil || model.selectedImage != nil { return nil }
        return available(for: model).contains(current) ? current : .look
    }
}

private enum StudioInspectorContent: Hashable {
    case page(StudioInspectorPage)
    case zoom(UUID)
    case layout(UUID)
    case text(UUID)
    case redaction(UUID)
    case image(UUID)
    case audio(UUID)
}

struct StudioInspector: View {
    @Bindable var model: RecordingStudioModel
    @Binding var page: StudioInspectorPage
    @State private var wallpaperStore = AnnotationWallpaperStore.shared
    @State private var stylePresetStore = RecordingStudioStylePresetStore.shared
    @State private var transcriptTab: StudioTranscriptTab = UpshotStorage.isRenderingStates && StateRenderer.scenario.contains("transcript") ? .edit : .captions
    @State private var isAudioExportOptionsPresented = false

    init(model: RecordingStudioModel, page: Binding<StudioInspectorPage>) {
        self.model = model
        self._page = page
    }

    init(model: RecordingStudioModel) {
        self.init(model: model, page: .constant(StudioInspectorPage.renderInitialPage))
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Space.xxl) {
                switch content {
                case .page(let page):
                    pageContent(page)
                case .zoom:
                    if let cue = model.selectedCue {
                        selectedZoomPage(for: cue)
                    }
                case .layout:
                    if let cue = model.selectedLayoutCue {
                        selectedLayoutPage(for: cue)
                    }
                case .text:
                    if let text = model.selectedText {
                        selectedTextPage(for: text)
                    }
                case .redaction:
                    if let redaction = model.selectedRedaction {
                        selectedRedactionPage(for: redaction)
                    }
                case .image:
                    if let image = model.selectedImage {
                        selectedImagePage(for: image)
                    }
                case .audio:
                    if let clip = model.selectedAudioClip {
                        selectedAudioPage(for: clip)
                    }
                }
            }
            .buttonStyle(.interfaceAction)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xl)
        }
        .id(content)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectSoftIfAvailable()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StudioActionFooter(model: model)
                .background(Palette.panel)
        }
        .background(Palette.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await wallpaperStore.reload()
        }
    }

    private var content: StudioInspectorContent {
        if let cue = model.selectedCue { return .zoom(cue.id) }
        if let cue = model.selectedLayoutCue { return .layout(cue.id) }
        if let text = model.selectedText { return .text(text.id) }
        if let redaction = model.selectedRedaction { return .redaction(redaction.id) }
        if let image = model.selectedImage { return .image(image.id) }
        if let clip = model.selectedAudioClip { return .audio(clip.id) }
        let available = StudioInspectorPage.available(for: model)
        return .page(available.contains(page) ? page : .look)
    }

    @ViewBuilder
    private func pageContent(_ page: StudioInspectorPage) -> some View {
        switch page {
        case .look: lookPage
        case .camera: cameraPage
        case .zoom: zoomPage
        case .cursor: cursorPage
        case .keystrokes: keystrokesPage
        case .captions: captionsPage
        case .audio: audioPage
        case .clip: clipPage
        }
    }

    private func group<Content: View, Accessory: View>(
        _ title: String,
        isOn: Binding<Bool>? = nil,
        toggleTitle: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        StudioInspectorGroup(title, isOn: isOn, toggleTitle: toggleTitle, accessory: accessory, content: content)
    }

    private func group<Content: View>(
        _ title: String,
        isOn: Binding<Bool>? = nil,
        toggleTitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        StudioInspectorGroup(title, isOn: isOn, toggleTitle: toggleTitle, content: content)
    }

    private func controls<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            content()
        }
    }

    private func modeSwitchRow<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [InterfaceModeSwitchOption<Value>]
    ) -> some View {
        StudioInspectorModeSwitchRow(title, selection: selection, options: options)
    }

    // MARK: Look

    @ViewBuilder
    private var lookPage: some View {
        RecordingStudioStyleStrip(model: model, presetStore: stylePresetStore)

        group("Background") {
            InspectorBackgroundRow(
                style: $model.style.background,
                wallpaperStore: wallpaperStore,
                onPickWallpaper: pickWallpaper,
                onPreview: { model.previewBackground($0, isHovering: $1) },
                onEndPreview: { model.previewBackground = nil }
            )
        }

        group("Frame", accessory: {
            if !usesDefaultLayout {
                InterfaceResetButton(help: "Reset padding, corners, and shadow") {
                    withAnimation(.morphIfAllowed) {
                        model.style.padding = 0.06
                        model.style.cornerRadius = 0.02
                        model.style.shadow = 0.45
                    }
                }
                .transition(.opacity)
            }
        }) {
            frameControls
        }

        group("Canvas") {
            controls {
                StudioInspectorPickerRow("Aspect ratio", selection: Binding(
                    get: { model.exportAspect },
                    set: { aspect in withAnimation(.morphIfAllowed) { model.exportAspect = aspect } }
                )) {
                    ForEach(ExportAspectPreset.allCases, id: \.self) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                if model.exportAspect != .original {
                    modeSwitchRow(
                        "Video",
                        selection: Binding(
                            get: { model.exportAspectMode },
                            set: { mode in withAnimation(.morphIfAllowed) { model.exportAspectMode = mode } }
                        ),
                        options: ExportAspectContentMode.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.title) }
                    )
                    .transition(.opacity)
                }

                StudioInspectorPickerRow("3D shot", selection: $model.exportAppearance.shot) {
                    ForEach(RecordingExportShot.allCases, id: \.self) { shot in
                        Text(shot.rawValue).tag(shot)
                    }
                }
                .help("Apply perspective to the screen card during export. Orbit animates the perspective.")
            }
        }
    }

    private var frameControls: some View {
        controls {
            InspectorFieldPair {
                InspectorSlider("Padding", value: $model.style.padding, range: 0...0.18, format: .percent())
            } trailing: {
                InspectorSlider("Corners", value: $model.style.cornerRadius, range: 0...0.08, format: .percent())
            }

            InspectorHalfField {
                InspectorSlider("Shadow", value: $model.style.shadow, range: 0...1, format: .percent())
                    .disabled(model.style.background == .none)
            }
        }
    }

    private func pickWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Video Background Wallpaper"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            wallpaperStore.addRecentWallpaper(url)
            model.style.background = .customWallpaper(AnnotationCustomWallpaper(url: url))
        }
    }

    // MARK: Camera

    @ViewBuilder
    private var cameraPage: some View {
        group("Camera", isOn: $model.style.camera.isVisible, toggleTitle: "Show camera") {
            StudioCameraLayoutPicker(model: model, layout: model.style.camera.layout) { layout, isContinuous in
                if isContinuous {
                    model.style.camera.layout = layout
                } else {
                    withAnimation(.morphQuickIfAllowed) { model.style.camera.layout = layout }
                }
            }
        }

        group("Touch Up") {
            InspectorFieldPair {
                InspectorSlider("Face light", value: $model.style.camera.beauty.faceLight, range: 0...1, format: .percent())
                    .help("Brightens the face's shadows and midtones")
            } trailing: {
                InspectorSlider("Smoothing", value: $model.style.camera.beauty.skinSmoothing, range: 0...1, format: .percent())
                    .help("Evens out skin and keeps eyes, brows, and lips sharp")
            }
        }
        .disabled(!model.style.camera.isVisible)
    }

    private func selectedLayoutPage(for selected: RecordingCameraLayoutCue) -> some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            selectionHeader("Camera Layout", onDone: { model.selectedLayoutCueID = nil })

            if !model.showsCameraLayer {
                InterfaceRowLabel("Camera is off", detail: "Turn on the camera on the Camera page to use layouts.")
            }

            StudioCameraLayoutPicker(model: model, layout: selected.layout) { layout, isContinuous in
                var updated = selected
                updated.layout = layout
                if isContinuous {
                    model.resizeLayoutCue(updated)
                } else {
                    model.updateLayoutCue(updated, actionName: "Change Layout")
                }
            }
            .disabled(!model.showsCameraLayer)
            .help("Morphs in at the start of this stretch and back to the default at its end")

            deleteButton("Delete Layout") {
                withAnimation(.morphIfAllowed) { model.removeLayoutCue(id: selected.id) }
            }
        }
    }

    // MARK: Zoom

    @ViewBuilder
    private var zoomPage: some View {
        let pressCount = model.recordedPressTimes.count
        group("Zoom", isOn: $model.zoomEnabled, toggleTitle: "Enable zooms") {
            controls {
                modeSwitchRow(
                    "Animation",
                    selection: $model.exportAppearance.zoomAnimationStyle,
                    options: RecordingZoomAnimationStyle.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.rawValue) }
                )

                HStack(spacing: Space.m) {
                    Button {
                        withAnimation(.morphIfAllowed) { model.addZoomCue(at: model.currentTime) }
                    } label: {
                        Label("Add Zoom", systemImage: "plus.magnifyingglass")
                    }
                    .help("Add a zoom at the playhead, or drag across the zoom lane")

                    Button {
                        withAnimation(.morphIfAllowed) { model.resynthesizeZoomCues() }
                    } label: {
                        Label("Auto Zoom", systemImage: "pointer.arrow.rays")
                    }
                    .disabled(pressCount == 0)
                    .help(
                        pressCount == 0
                            ? "No clicks were recorded"
                            : "Turn the \(pressCount == 1 ? "recorded click" : "\(pressCount) recorded clicks") into zooms"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func selectedZoomPage(for selected: ZoomCue) -> some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            selectionHeader("Zoom", onDone: { model.selectedCueID = nil })

            if !model.zoomEnabled {
                InterfaceRow("Zooms are off") {
                    Button("Turn On") {
                        withAnimation(.morphIfAllowed) { model.zoomEnabled = true }
                    }
                }
            } else {
                group(
                    "This Zoom",
                    isOn: Binding(
                        get: { selected.isEnabled },
                        set: { isEnabled in
                            var updated = selected
                            updated.isEnabled = isEnabled
                            model.updateZoomCue(updated)
                        }
                    ),
                    toggleTitle: "Use this zoom"
                ) {
                    selectedZoomControls(for: selected)
                }
            }

            deleteButton("Delete Zoom") {
                withAnimation(.morphIfAllowed) { model.removeZoomCue(id: selected.id) }
            }
        }
    }

    private func selectedZoomControls(for selected: ZoomCue) -> some View {
        controls {
            modeSwitchRow(
                "Focus",
                selection: Binding(
                    get: { selected.anchorMode },
                    set: { anchorMode in
                        var updated = selected
                        updated.anchorMode = anchorMode
                        if anchorMode == .pinnedAnchor,
                           let pointer = model.pointerLocation(at: model.currentTime) {
                            updated.pinnedPoint = pointer
                        }
                        withAnimation(.morphIfAllowed) { model.updateZoomCue(updated) }
                    }
                ),
                options: ZoomAnchorMode.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.inspectorTitle) }
            )

            if selected.anchorMode == .pinnedAnchor {
                InspectorHalfField {
                    zoomAmountSlider(for: selected)
                }

                InterfaceRow("Target") {
                    Text(zoomTargetPositionText(selected.pinnedPoint))
                        .font(.dsFieldNumeric)
                        .foregroundStyle(Palette.secondaryLabel)
                }

                RecordingZoomFocusPad(
                    position: Binding(
                        get: { selected.pinnedPoint },
                        set: { target in
                            var updated = selected
                            updated.pinnedPoint = target
                            model.updateZoomCue(updated)
                        }
                    ),
                    magnification: selected.zoom
                )

                Button {
                    guard let pointer = model.pointerLocation(at: model.currentTime) else { return }
                    var updated = selected
                    updated.pinnedPoint = pointer
                    withAnimation(.morphIfAllowed) { model.updateZoomCue(updated) }
                } label: {
                    Label("Target Pointer", systemImage: "scope")
                }
                .help("Aim the zoom at the pointer's position under the playhead")
            } else {
                InspectorFieldPair {
                    zoomAmountSlider(for: selected)
                } trailing: {
                    InspectorSlider(
                        "Edge",
                        value: Binding(
                            get: { CGFloat(selected.boundsBias) },
                            set: { boundsBias in
                                var updated = selected
                                updated.boundsBias = Double(boundsBias)
                                model.updateZoomCue(updated)
                            }
                        ),
                        range: 0...1,
                        format: .percent()
                    )
                    .help("How much of the frame's edge stays in view while zoomed")
                }
            }
        }
    }

    private func zoomAmountSlider(for selected: ZoomCue) -> some View {
        InspectorSlider(
            "Zoom",
            value: Binding(
                get: { CGFloat(selected.zoom) },
                set: { newValue in
                    var updated = selected
                    updated.zoom = Double(newValue)
                    model.updateZoomCue(updated)
                }
            ),
            range: 1.1...3,
            format: .magnification(fractionDigits: 1)
        )
    }

    private func zoomTargetPositionText(_ position: CGPoint) -> String {
        let x = Int((position.x * 100).rounded())
        let y = Int((position.y * 100).rounded())
        return "\(x), \(y)"
    }

    // MARK: Cursor

    @ViewBuilder
    private var cursorPage: some View {
        group(
            "Cursor",
            isOn: Binding(
                get: { !model.style.hidesCursor },
                set: { model.style.hidesCursor = !$0 }
            ),
            toggleTitle: "Show mouse pointer",
            accessory: {
                if model.style.cursorScale != RecordingStudioStyle.defaultCursorScale, !model.style.hidesCursor {
                    InterfaceResetButton(help: "Reset cursor size") {
                        withAnimation(.morphIfAllowed) {
                            model.style.cursorScale = RecordingStudioStyle.defaultCursorScale
                        }
                    }
                    .transition(.opacity)
                }
            }
        ) {
            controls {
                StudioCursorStylePicker(
                    selection: $model.style.cursorStyle,
                    inverted: model.style.invertsCursor
                )

                InspectorHalfField {
                    InspectorSlider("Size", value: $model.style.cursorScale, range: 1...4, format: .magnification(fractionDigits: 1))
                }

                if let shape = model.style.cursorStyle.shape, !shape.isCircle {
                    InterfaceToggleRow("Invert colors", isOn: $model.style.invertsCursor)
                }

                if model.canShowPressEffects {
                    InterfaceToggleRow("Click highlights", isOn: $model.showsClickEffects)
                }
            }
        }
    }

    // MARK: Keystrokes

    @ViewBuilder
    private var keystrokesPage: some View {
        group("Keystrokes", isOn: $model.showsKeystrokes, toggleTitle: "Show keystrokes") {
            controls {
                modeSwitchRow(
                    "Size",
                    selection: $model.exportAppearance.keystrokes.size,
                    options: RecordingKeystrokeSize.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.rawValue) }
                )
                modeSwitchRow(
                    "Style",
                    selection: $model.exportAppearance.keystrokes.style,
                    options: RecordingKeystrokeStyle.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.rawValue) }
                )
                StudioInspectorPickerRow("Position", selection: Binding(
                    get: { model.exportAppearance.keystrokes.resolvedPosition(fallback: model.keystrokePlacement) },
                    set: { model.exportAppearance.keystrokes.position = $0 }
                )) {
                    ForEach(RecordingKeystrokePosition.allCases, id: \.self) { position in
                        Text(position.title).tag(position)
                    }
                }
                StudioInspectorPickerRow("Keys", selection: $model.exportAppearance.keystrokes.filter) {
                    ForEach(RecordingKeystrokeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .help("Typed keys stay hidden with Command Keys Only. All Keys shows typed keys only when their capture was on before recording.")
            }
        }
    }

    // MARK: Captions

    @ViewBuilder
    private var captionsPage: some View {
        group("Captions", isOn: captionsToggle, toggleTitle: "Show subtitles", accessory: {
            if model.transcriptionState.isTranscribing {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }) {
            transcriptionControls
        }
    }

    private var captionsToggle: Binding<Bool>? {
        guard model.hasSubtitles, case .idle = model.transcriptionState else { return nil }
        return $model.showsSubtitles
    }

    @ViewBuilder
    private var transcriptionControls: some View {
        controls {
            switch model.transcriptionState {
            case .transcribing:
                InterfaceRowLabel("Transcribing narration on this Mac…")
                    .transition(.opacity)
            case .failed(let message):
                InterfaceRowLabel("Transcription failed", detail: message, detailIsCritical: true)
                Button {
                    model.transcribe()
                } label: {
                    Label("Try Again", systemImage: "waveform")
                }
            case .idle:
                if model.hasSubtitles {
                    subtitleEditor
                } else {
                    Button {
                        withAnimation(.morphIfAllowed) { model.transcribe() }
                    } label: {
                        Label("Transcribe Narration", systemImage: "waveform")
                    }
                    .help("Turn the microphone narration into subtitles, transcribed on this Mac")
                }
            }
        }
    }

    private var subtitleEditor: some View {
        controls {
            InterfaceModeSwitch(
                "Transcript mode",
                selection: Binding(
                    get: { transcriptTab },
                    set: { tab in withAnimation(.morphQuickIfAllowed) { transcriptTab = tab } }
                ),
                options: [
                    InterfaceModeSwitchOption(value: StudioTranscriptTab.captions, title: "Captions"),
                    InterfaceModeSwitchOption(value: StudioTranscriptTab.edit, title: "Edit Video")
                ]
            )

            switch transcriptTab {
            case .captions:
                captionControls
                    .transition(.opacity)
            case .edit:
                transcriptEditControls
                    .transition(.opacity)
            }

            HStack(spacing: Space.m) {
                if model.canTranscribe {
                    Button {
                        withAnimation(.morphIfAllowed) { model.transcribe() }
                    } label: {
                        Label("Transcribe Again", systemImage: "arrow.clockwise")
                    }
                }

                Button(role: .destructive) {
                    withAnimation(.morphIfAllowed) { model.removeTranscription() }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .help("Remove the subtitles")
            }
        }
    }

    private var captionControls: some View {
        let verticalRange = SubtitleBarStyle.verticalRange
        let fontScaleRange = SubtitleBarStyle.fontScaleRange
        return controls {
            InspectorFieldPair {
                InspectorSlider(
                    "Position",
                    value: Binding(
                        get: { CGFloat(model.subtitleStyle.verticalPosition) },
                        set: { model.subtitleStyle.verticalPosition = Double($0) }
                    ),
                    range: CGFloat(verticalRange.lowerBound)...CGFloat(verticalRange.upperBound),
                    format: .percent()
                )
            } trailing: {
                InspectorSlider(
                    "Size",
                    value: Binding(
                        get: { CGFloat(model.subtitleStyle.fontScale) },
                        set: { model.subtitleStyle.fontScale = Double($0) }
                    ),
                    range: CGFloat(fontScaleRange.lowerBound)...CGFloat(fontScaleRange.upperBound),
                    format: .magnification(fractionDigits: 1)
                )
            }

            if model.hasTranscriptWords {
                InterfaceToggleRow("Highlight spoken word", isOn: $model.subtitleStyle.highlightsSpokenWord)
            }

            subtitleList
                .help("Click a timestamp to jump there. Edit any line to fix the transcription.")
        }
    }

    @ViewBuilder
    private var transcriptEditControls: some View {
        controls {
            if model.hasTranscriptWords {
                StudioTranscriptEditPanel(model: model)
                    .help("Click a word to jump there. Shift-click to select a passage, then cut it.")

                if model.removableFillerWordCount > 0 || model.trimmableSilenceCount > 0 {
                    HStack(spacing: Space.m) {
                        if model.removableFillerWordCount > 0 {
                            Button {
                                withAnimation(.morphIfAllowed) { model.removeFillerWords() }
                            } label: {
                                Label(model.removableFillerWordCount == 1 ? "Cut 1 Filler" : "Cut \(model.removableFillerWordCount) Fillers", systemImage: "scissors")
                            }
                            .help("Cut every filler word, like “um” and “uh”")
                            .transition(.opacity)
                        }

                        if model.trimmableSilenceCount > 0 {
                            Button {
                                withAnimation(.morphIfAllowed) { model.trimNarrationSilences() }
                            } label: {
                                Label(model.trimmableSilenceCount == 1 ? "Trim 1 Pause" : "Trim \(model.trimmableSilenceCount) Pauses", systemImage: "waveform.badge.minus")
                            }
                            .help("Trim long pauses in the narration")
                            .transition(.opacity)
                        }
                    }
                }
            } else {
                InterfaceRowLabel("Transcribe again to edit the video by its transcript.")
            }
        }
    }

    private var subtitleList: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    let cues = model.subtitleCues
                    ForEach(Array(cues.enumerated()), id: \.element.id) { index, cue in
                        StudioSubtitleRow(
                            model: model,
                            cue: cue,
                            isActive: model.activeSubtitleCue?.id == cue.id
                        )
                        .id(cue.id)

                        if index < cues.count - 1 {
                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(height: 1)
                                .padding(.leading, Space.ml)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .background(shape.fill(Palette.fieldFill))
            .overlay { shape.strokeBorder(Palette.fieldStroke, lineWidth: 1) }
            .clipShape(shape)
            .onChange(of: model.activeSubtitleCue?.id) { _, activeID in
                guard let activeID, model.isPlaying else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(activeID, anchor: .center)
                }
            }
        }
    }

    // MARK: Audio

    @ViewBuilder
    private var audioPage: some View {
        group("Audio", accessory: {
            if model.replacementAudio != nil, model.hasRecordedAudio {
                InterfaceResetButton(help: "Use the recorded audio again") {
                    withAnimation(.morphIfAllowed) { model.removeReplacementAudio() }
                }
                .transition(.opacity)
            }
        }) {
            controls {
                if model.hasAudio {
                    InspectorHalfField {
                        InspectorSlider("Volume", value: $model.audioVolume, range: 0...2, format: .percent())
                    }
                    InterfaceToggleRow("Mono export", isOn: $model.exportDeliveryOptions.monoAudio)
                }

                if let replacement = model.replacementAudio {
                    replacementRow(for: replacement)
                        .transition(.opacity)
                }

                if let message = model.replacementAudioError {
                    InterfaceRowLabel("Audio not added", detail: message, detailIsCritical: true)
                        .transition(.opacity)
                }

                HStack(spacing: Space.m) {
                    Button {
                        pickReplacementAudio()
                    } label: {
                        Label(model.hasRecordedAudio ? "Replace…" : "Add Audio…", systemImage: "waveform.badge.plus")
                    }
                    .help(
                        model.hasRecordedAudio
                            ? "Swap in an audio file, aligned to the start of the edited timeline"
                            : "Lay an audio file over this silent recording"
                    )

                    if model.replacementAudio != nil, !model.hasRecordedAudio {
                        Button(role: .destructive) {
                            withAnimation(.morphIfAllowed) { model.removeReplacementAudio() }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }

                    if model.hasAudio {
                        audioExportButton
                    }
                }
            }
        }
        .motion(.morph, value: model.replacementAudio?.displayName)
    }

    @ViewBuilder
    private var audioExportButton: some View {
        Group {
            switch model.audioExportState {
            case .idle:
                Button {
                    isAudioExportOptionsPresented = true
                } label: {
                    Label("Export…", systemImage: "arrow.down.circle")
                }
                .help("Export the soundtrack of the current cut")
                .popover(isPresented: $isAudioExportOptionsPresented, arrowEdge: .bottom) {
                    StudioAudioExportOptions(format: $model.audioExportFormat) {
                        isAudioExportOptionsPresented = false
                        model.exportAudio()
                    }
                }
            case .exporting(let progress):
                Button {
                    model.cancelAudioExport()
                } label: {
                    HStack(spacing: InterfaceMetrics.actionButtonIconToLabelSpacing) {
                        StudioProgressRing(progress: progress, size: IconSize.actionButton)
                        Text("\(Int((progress * 100).rounded()))%")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .help("Cancel the audio export")
            case .finished(let url):
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Reveal", systemImage: "checkmark.circle")
                }
                .help("Reveal \(url.lastPathComponent) in Finder")
            case .failed(let message):
                Button {
                    model.exportAudio()
                } label: {
                    Label("Retry", systemImage: "exclamationmark.triangle")
                }
                .help(message)
            }
        }
        .transition(.opacity)
        .motion(.morphQuick, value: model.audioExportState.phase)
    }

    private func replacementRow(for replacement: RecordingReplacementAudio) -> some View {
        InterfaceRow(replacement.displayName, systemImage: "waveform") {
            HStack(spacing: Space.xs) {
                if let drift = model.replacementAudioDrift {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: IconSize.row))
                        .foregroundStyle(Palette.warning)
                        .help(
                            drift > 0
                                ? "Runs \(Self.spanText(drift)) longer than the cut, so the end is dropped"
                                : "Runs \(Self.spanText(-drift)) shorter than the cut, so the end plays silent"
                        )
                }
                Text(Self.clockText(replacement.duration))
                    .font(.dsFieldNumeric)
                    .foregroundStyle(Palette.secondaryLabel)
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .help(replacement.displayName)
    }

    private func pickReplacementAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = RecordingAudioFormat.importContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose Replacement Audio"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.replaceAudio(with: url)
        }
    }

    private static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func spanText(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        return value < 60 ? String(format: "%.1fs", value) : clockText(value)
    }

    // MARK: Clip

    private var shownClip: RecordingClipSegment? {
        if let selected = model.selectedClip { return selected }
        guard let location = model.clipTimeline.location(at: model.currentTime) else {
            return model.clipTimeline.segments.first
        }
        return model.clipTimeline.segments.first { $0.id == location.segmentID }
    }

    private func clipTitle(for clip: RecordingClipSegment) -> String {
        let segments = model.clipTimeline.segments
        guard segments.count > 1,
              let index = segments.firstIndex(where: { $0.id == clip.id }) else {
            return "Clip"
        }
        return "Clip \(index + 1) of \(segments.count)"
    }

    @ViewBuilder
    private var clipPage: some View {
        if let clip = shownClip {
            group(clipTitle(for: clip)) {
                controls {
                    StudioInspectorPickerRow("Speed", selection: Binding(
                        get: { RecordingClipSegment.speedPresets.first { abs($0 - clip.speed) < 0.001 } ?? clip.speed },
                        set: { model.setClipSpeed($0, forClipID: clip.id) }
                    )) {
                        ForEach(RecordingClipSegment.speedPresets, id: \.self) { speed in
                            Text(RecordingClipSegment.speedTitle(speed)).tag(speed)
                        }
                    }
                    .help("Speed of the clip under the playhead. Audio speeds up with it.")

                    if model.canDeleteSelectedClip {
                        Button(role: .destructive) {
                            withAnimation(.morphIfAllowed) { model.deleteSelectedClip() }
                        } label: {
                            Label("Delete Clip", systemImage: "trash")
                        }
                    }
                }
            }
        }

        if model.hasSpedUpClips || (shownClip?.speed ?? 1) > 1.001 {
            group("Speed Badge", isOn: Binding(
                get: { model.showsSpeedBadge },
                set: { value in withAnimation(.morphIfAllowed) { model.showsSpeedBadge = value } }
            ), toggleTitle: "Show speed badge") {
                StudioInspectorPickerRow("Position", selection: $model.speedBadgePlacement) {
                    ForEach(RecordingKeystrokePlacement.allCases) { placement in
                        Text("\(placement.isTop ? "Top" : "Bottom") \(placement.title.lowercased())").tag(placement)
                    }
                }
            }
            .help("Sped-up clips carry a “2× ›››” badge while they play")
            .transition(.opacity)
        }
    }

    // MARK: Selection pages

    private func selectionHeader(_ title: String, onDone: @escaping () -> Void) -> some View {
        HStack(spacing: Space.m) {
            InterfaceSectionHeader(title)
            Spacer(minLength: Space.l)
            Button("Done", action: onDone)
                .keyboardShortcut(model.isCroppingVideo ? nil : .cancelAction)
                .help("Close this item and return to \(page.title)")
        }
        .frame(minHeight: InterfaceMetrics.rowMinimumHeight)
    }

    private func deleteButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: "trash")
        }
    }

    private func selectedTextPage(for text: RecordingTextOverlay) -> some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            selectionHeader("Text", onDone: { model.selectedTextID = nil })
            StudioTextInspectorControls(model: model, text: text)
            deleteButton("Delete Text") {
                withAnimation(.morphIfAllowed) { model.removeText(id: text.id) }
            }
        }
    }

    private func selectedRedactionPage(for redaction: RecordingRedaction) -> some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            selectionHeader(redaction.style.title, onDone: { model.selectedRedactionID = nil })
            StudioRedactionInspectorControls(model: model, redaction: redaction)
            deleteButton("Delete \(redaction.style.title)") {
                withAnimation(.morphIfAllowed) { model.removeRedaction(id: redaction.id) }
            }
        }
    }

    private func selectedImagePage(for image: RecordingImageOverlay) -> some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            selectionHeader(image.isAnimated ? "GIF" : "Image", onDone: { model.selectedImageID = nil })
            StudioImageInspectorControls(model: model, image: image)
            deleteButton(image.isAnimated ? "Delete GIF" : "Delete Image") {
                withAnimation(.morphIfAllowed) { model.removeImage(id: image.id) }
            }
        }
    }

    private func selectedAudioPage(for clip: RecordingAudioClip) -> some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            selectionHeader(clip.displayName, onDone: { model.selectedAudioClipID = nil })
            StudioAudioClipInspectorControls(model: model, clip: clip)
            deleteButton("Delete Audio") {
                withAnimation(.morphIfAllowed) { model.removeAudioClip(id: clip.id) }
            }
        }
    }

    private var usesDefaultLayout: Bool {
        abs(model.style.padding - 0.06) < 0.0001
            && abs(model.style.cornerRadius - 0.02) < 0.0001
            && abs(model.style.shadow - 0.45) < 0.0001
    }
}

private extension RecordingStudioExportState {
    var phase: Int {
        switch self {
        case .idle: 0
        case .exporting: 1
        case .finished: 2
        case .failed: 3
        }
    }
}

private struct StudioSubtitleRow: View {
    @Bindable var model: RecordingStudioModel
    let cue: RecordingSubtitleCue
    let isActive: Bool

    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Button {
                model.seekToSubtitle(cue)
            } label: {
                Text(timestamp ?? "–:––")
                    .font(.dsCaption.monospacedDigit())
                    .foregroundStyle(isActive ? Palette.label : Palette.secondaryLabel)
            }
            .buttonStyle(.plain)
            .disabled(editorTime == nil)
            .help(editorTime == nil ? "This subtitle's audio was cut out" : "Jump to this subtitle")

            TextField(
                "Subtitle",
                text: Binding(
                    get: { cue.text },
                    set: { model.updateSubtitleText(id: cue.id, text: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.dsBody)
            .foregroundStyle(Palette.label)
            .focused($isEditing)
            .onChange(of: isEditing) { _, editing in
                if editing {
                    model.seekToSubtitle(cue)
                }
            }
        }
        .padding(.horizontal, Space.ml)
        .padding(.vertical, Space.s)
        .background(isActive ? Palette.sidebarSelectionFill : .clear)
        .contentShape(Rectangle())
        .opacity(editorTime == nil ? 0.45 : 1)
        .onTapGesture {
            model.seekToSubtitle(cue)
        }
        .onHover { hovering in
            guard !model.isPlaying, let editorTime else { return }
            if hovering {
                model.hoverPreviewTime = editorTime
            } else if model.hoverPreviewTime == editorTime {
                model.hoverPreviewTime = nil
            }
        }
    }

    private var editorTime: TimeInterval? {
        model.editorTime(forSourceTime: cue.start)
            ?? model.editorTime(forSourceTime: (cue.start + cue.end) / 2)
    }

    private var timestamp: String? {
        guard let editorTime else { return nil }
        let total = max(0, Int(editorTime.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct StudioTranscriptEditPanel: View {
    @Bindable var model: RecordingStudioModel

    @State private var selection: ClosedRange<Int>?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    transcriptFlow
                        .padding(Space.m)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: 260)
                .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(Palette.fieldFill))
                .overlay { RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Palette.fieldStroke, lineWidth: 1) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .onChange(of: model.activeTranscriptWordIndex) { _, activeIndex in
                    guard let activeIndex, model.isPlaying, selection == nil else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(activeIndex, anchor: .center)
                    }
                }
            }

            if let selection {
                cutSelectionRow(selection)
            }
        }
        .onDeleteCommand(perform: cutSelection)
        .onExitCommand { selection = nil }
    }

    private var transcriptFlow: some View {
        let activeIndex = model.activeTranscriptWordIndex
        return TranscriptFlowLayout() {
            ForEach(model.transcriptWords.indices, id: \.self) { index in
                StudioTranscriptWordView(
                    text: model.transcriptWords[index].displayText,
                    isSelected: selection?.contains(index) ?? false,
                    isActive: index == activeIndex,
                    isCut: !model.transcriptWordSurvives(index),
                    isFiller: model.isFillerWord(index)
                ) {
                    handleTap(on: index)
                }
                .id(index)
            }
        }
    }

    private func cutSelectionRow(_ selection: ClosedRange<Int>) -> some View {
        HStack(spacing: Space.m) {
            Button(role: .destructive, action: cutSelection) {
                Label(selection.count == 1 ? "Cut Word" : "Cut \(selection.count) Words", systemImage: "scissors")
            }

            Button("Clear") {
                self.selection = nil
            }
            .help("Clear the selection")
        }
    }

    private func handleTap(on index: Int) {
        let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if shiftHeld, let selection {
            self.selection = min(selection.lowerBound, index)...max(selection.upperBound, index)
        } else {
            selection = index...index
            model.seekToTranscriptWord(at: index)
        }
    }

    private func cutSelection() {
        guard let selection else { return }
        model.cutTranscriptWords(in: selection)
        self.selection = nil
    }
}

private struct StudioTranscriptWordView: View {
    let text: String
    let isSelected: Bool
    let isActive: Bool
    let isCut: Bool
    let isFiller: Bool
    let action: () -> Void

    var body: some View {
        Text(text)
            .font(.dsCallout)
            .foregroundStyle(foreground)
            .strikethrough(isCut, color: .secondary.opacity(0.6))
            .padding(.horizontal, 1.5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private var foreground: Color {
        isCut ? Palette.tertiaryLabel : Palette.label
    }

    private var background: Color {
        if isSelected {
            Palette.highlight.opacity(isCut ? 0.12 : 0.24)
        } else if isActive, !isCut {
            Palette.highlight.opacity(0.2)
        } else if isFiller, !isCut {
            Palette.warning.opacity(0.16)
        } else {
            Color.clear
        }
    }
}

private struct TranscriptFlowLayout: Layout {
    var spacingX: CGFloat = 0
    var spacingY: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 240
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacingY
                rowHeight = 0
            }
            x += size.width + spacingX
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacingY
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacingX
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct StudioAudioExportOptions: View {
    @Binding var format: RecordingAudioFormat
    let onExport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ExportAndShareOptionsPopoverLayout(
            confirmTitle: "Export Audio",
            width: 280,
            onCancel: { dismiss() },
            onConfirm: onExport
        ) {
            InterfaceSection(nil) {
                InterfaceRow("Format") {
                    InterfaceModeSwitch(
                        "Format",
                        selection: $format,
                        options: RecordingAudioFormat.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.title) }
                    )
                }
                .help(format == .m4a
                    ? "M4A is compact AAC audio, accepted by most enhancement tools."
                    : "WAV is uncompressed, for tools that accept nothing else.")
            }
        }
    }
}

private struct StudioCursorStylePicker: View {
    @Binding var selection: RecordingCursorStyle
    let inverted: Bool

    private struct Preview {
        var image: NSImage
        var size: CGSize
        var glyph: CGRect
    }

    private struct PreviewKey: Hashable {
        var style: RecordingCursorStyle
        var inverted: Bool
    }

    private static let previews: [PreviewKey: Preview] = {
        var previews: [PreviewKey: Preview] = [:]
        for style in RecordingCursorStyle.allCases {
            for inverted in [false, true] {
                let artwork = style.shape?.artwork(inverted: inverted) ?? PointerArtworkCapture.defaultArtwork()
                if let artwork, let image = NSImage(data: artwork.imageData) {
                    previews[PreviewKey(style: style, inverted: inverted)] = Preview(
                        image: image,
                        size: CGSize(width: artwork.referenceSize.width, height: artwork.referenceSize.height),
                        glyph: opaqueBounds(of: image)
                    )
                }
            }
        }
        return previews
    }()

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(RecordingCursorStyle.allCases, id: \.self) { style in
                InspectorTile(title: style.title, isSelected: selection == style) {
                    selection = style
                } content: {
                    preview(style)
                }
            }
        }
    }

    private func preview(_ style: RecordingCursorStyle) -> some View {
        GeometryReader { proxy in
            if let preview = Self.previews[PreviewKey(style: style, inverted: inverted)] {
                let scale = proxy.size.width / 40
                let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
                let shape = style.shape
                if shape?.isCircle == true {
                    textLines(in: proxy.size)
                }
                Image(nsImage: preview.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .background {
                        if let material = shape?.material {
                            PointerMaterialView(
                                material: material,
                                diameter: size.width * PointerShape.circleRadiusRatio * 2
                            )
                        }
                    }
                    .offset(
                        x: proxy.size.width / 2 - preview.glyph.midX * size.width,
                        y: proxy.size.height / 2 - preview.glyph.midY * size.height
                    )
            }
        }
        .background(Color.primary.opacity(0.05))
    }

    private func textLines(in size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: size.height * 0.1) {
            ForEach([0.62, 0.48, 0.56], id: \.self) { fraction in
                Capsule()
                    .fill(Color.primary.opacity(0.4))
                    .frame(width: size.width * fraction, height: size.height * 0.08)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private static func opaqueBounds(of image: NSImage) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
              ) else {
            return full
        }
        let width = cgImage.width
        let height = cgImage.height
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return full }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] > 64 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return full }
        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }
}
