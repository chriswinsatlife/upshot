import SwiftUI

enum RecordingExportPreferences {
    private static let settingsKey = "recordingExportDefaultSettings"
    private static let hevcDefaultKey = "recordingExportDefaultsMovedToHEVC"

    static var lastSettings: VideoCompressionSettings {
        get {
            guard let data = UpshotStorage.defaults.data(forKey: settingsKey),
                  var decoded = try? JSONDecoder().decode(
                    VideoCompressionSettings.self,
                    from: data
                  ) else {
                return VideoCompressionSettings()
            }
            if !UpshotStorage.defaults.bool(forKey: hevcDefaultKey) {
                UpshotStorage.defaults.set(true, forKey: hevcDefaultKey)
                if decoded.codec == .h264 {
                    decoded.codec = .hevc
                    lastSettings = decoded
                }
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UpshotStorage.defaults.set(data, forKey: settingsKey)
        }
    }
}

struct RecordingExportOptionsPopover: View {
    let initialSettings: VideoCompressionSettings
    let onConfirm: (VideoCompressionSettings) -> Void

    @State private var settings: VideoCompressionSettings
    @State private var delivery = UpshotPreferences.recordingExtendedExportDefaults
    @Environment(\.dismiss) private var dismiss

    init(
        initialSettings: VideoCompressionSettings,
        initialDeliveryOptions: RecordingExportDeliveryOptions? = nil,
        onConfirm: @escaping (VideoCompressionSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.onConfirm = onConfirm
        _settings = State(initialValue: initialSettings)
        _delivery = State(initialValue: initialDeliveryOptions ?? UpshotPreferences.recordingExtendedExportDefaults)
    }

    var body: some View {
        ExportAndShareOptionsPopoverLayout(
            confirmTitle: delivery.format == .gif ? "Export GIF" : "Export Video",
            onCancel: { dismiss() },
            onConfirm: confirm
        ) {
            InterfaceModeSwitch(
                "Output",
                selection: $delivery.format,
                options: RecordingExportFormat.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.rawValue) }
            )
            .frame(maxWidth: .infinity)
        } content: {
            if delivery.format == .gif {
                gifSection
            } else {
                videoSection
                audioSection
            }
        }
    }

    private var videoSection: some View {
        InterfaceSection(nil) {
            modeSwitchRow("Quality", selection: $settings.quality, options: VideoCompressionQuality.allCases)
            modeSwitchRow("Codec", selection: $settings.codec, options: VideoCompressionCodec.allCases)
            resolutionRow
            modeSwitchRow(
                "Frame rate",
                selection: Binding(get: { settings.effectiveFrameRate }, set: { settings.frameRate = $0 }),
                options: VideoExportFrameRate.allCases
            )
            motionBlurRow
            modeSwitchRow(
                "Format",
                selection: Binding(get: { settings.effectiveContainer }, set: { settings.container = $0 }),
                options: VideoExportContainer.allCases
            )
            .help(containerHelp)
            InterfaceToggleRow("Scale Retina to 1x", isOn: $delivery.scalesRetinaToOne)
        }
    }

    private var audioSection: some View {
        InterfaceSection(nil) {
            InterfaceToggleRow("Include audio", isOn: Binding(
                get: { !settings.removeAudio },
                set: { settings.removeAudio = !$0 }
            ))
            InterfaceToggleRow("Mono audio", isOn: $delivery.monoAudio)
                .disabled(settings.removeAudio)
            InterfaceToggleRow("Separate audio tracks", isOn: $delivery.separateAudioTracks)
                .disabled(settings.removeAudio)
                .help("Keep microphone and system audio as independent tracks. Added audio uses its own mixed track. An imported replacement soundtrack replaces the recorded tracks.")
        }
    }

    private var gifSection: some View {
        InterfaceSection(nil) {
            InterfacePickerRow("Frame rate", selection: $delivery.gifFrameRate) {
                ForEach(RecordingGIFFrameRate.allCases, id: \.self) { rate in
                    Text("\(rate.rawValue) fps").tag(rate)
                }
            }
            modeSwitchRow("Quality", selection: $delivery.gifQuality, options: RecordingGIFQuality.allCases.reversed())
            resolutionRow
            motionBlurRow
            InterfaceToggleRow("Scale Retina to 1x", isOn: $delivery.scalesRetinaToOne)
            InterfaceToggleRow("Optimize", isOn: $delivery.optimizesGIF)
                .help("Combine identical frames. GIF exports loop continuously and contain no audio.")
        }
    }

    private var resolutionRow: some View {
        InterfacePickerRow("Resolution", selection: $settings.resolution) {
            ForEach(VideoCompressionResolution.allCases) { resolution in
                Text(resolution.rawValue).tag(resolution)
            }
        }
    }

    private var motionBlurRow: some View {
        InterfacePickerRow(
            "Motion blur",
            selection: Binding(
                get: { delivery.motionBlurLevel ?? (settings.effectiveMotionBlurEnabled ? .high : .off) },
                set: { delivery.motionBlurLevel = $0 }
            )
        ) {
            ForEach(RecordingMotionBlurLevel.allCases, id: \.self) { level in
                Text(level.rawValue).tag(level)
            }
        }
    }

    private var containerHelp: String {
        switch settings.effectiveContainer {
        case .mov:
            "MOV is the native QuickTime format for Apple apps."
        case .mp4:
            "MP4 plays on more platforms, including Windows, browsers, and Slack."
        }
    }

    private func confirm() {
        let confirmed = settings
        RecordingExportPreferences.lastSettings = confirmed
        UpshotPreferences.recordingExtendedExportDefaults = delivery
        dismiss()
        onConfirm(confirmed)
    }

    private func modeSwitchRow<Option: Hashable & RawRepresentable>(
        _ title: String,
        selection: Binding<Option>,
        options: [Option]
    ) -> some View where Option.RawValue == String {
        InterfaceRow(title) {
            InterfaceModeSwitch(
                title,
                selection: selection,
                options: options.map { InterfaceModeSwitchOption(value: $0, title: $0.rawValue) }
            )
        }
    }
}

struct RecordingExportButton<Label: View>: View {
    let currentSettings: VideoCompressionSettings
    let onExport: (VideoCompressionSettings) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showingOptions = false

    var body: some View {
        Button {
            showingOptions = true
        } label: {
            label()
        }
        .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
            RecordingExportOptionsPopover(
                initialSettings: currentSettings,
                onConfirm: onExport
            )
        }
    }
}
