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
                    Self.lastSettings = decoded
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
    let canvasSize: CGSize?
    let onConfirm: (VideoCompressionSettings) -> Void

    @State private var settings: VideoCompressionSettings
    @State private var delivery = UpshotPreferences.recordingExtendedExportDefaults
    @Environment(\.dismiss) private var dismiss

    init(
        initialSettings: VideoCompressionSettings,
        initialDeliveryOptions: RecordingExportDeliveryOptions? = nil,
        canvasSize: CGSize? = nil,
        onConfirm: @escaping (VideoCompressionSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.canvasSize = canvasSize
        self.onConfirm = onConfirm
        _settings = State(initialValue: initialSettings)
        _delivery = State(initialValue: initialDeliveryOptions ?? UpshotPreferences.recordingExtendedExportDefaults)
    }

    var body: some View {
        ExportAndShareOptionsPopoverLayout(
            confirmTitle: delivery.format == .gif ? "Export GIF" : "Export Video",
            isConfirmDisabled: delivery.format == .video && settings.resolution == .custom && !settings.hasValidCustomResolution,
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
        .onChange(of: settings) { _, _ in
            AppLog.event("recording", "export_settings_changed", fields: [
                "resolution": settings.resolution.rawValue,
                "frameRate": settings.effectiveFrameRate.rawValue,
                "encoding": settings.encodingMode?.rawValue ?? "legacy"
            ])
        }
        .onChange(of: delivery) { _, _ in
            AppLog.event("recording", "export_delivery_changed", fields: [
                "format": delivery.format.rawValue, "gifSize": delivery.gifSize?.rawValue ?? "legacy",
                "gifLoops": String(delivery.effectiveGIFLoops), "gifFPS": String(delivery.gifFrameRate.rawValue)
            ])
        }
    }

    private var videoSection: some View {
        InterfaceSection(nil) {
            modeSwitchRow("Quality", selection: $settings.quality, options: VideoCompressionQuality.allCases)
            modeSwitchRow("Codec", selection: $settings.codec, options: VideoCompressionCodec.allCases)
            modeSwitchRow(
                "Encoding",
                selection: Binding(get: { settings.effectiveEncodingMode }, set: { settings.encodingMode = $0 }),
                options: VideoExportEncodingMode.allCases
            )
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
            InterfacePickerRow("Size", selection: $delivery.gifSize) {
                if delivery.gifSize == nil {
                    Text(settings.resolution.rawValue).tag(nil as RecordingGIFSize?)
                }
                ForEach(RecordingGIFSize.allCases, id: \.self) { size in
                    Text(size.rawValue).tag(Optional(size))
                }
            }
            InterfaceToggleRow("Loop", isOn: Binding(
                get: { delivery.effectiveGIFLoops }, set: { delivery.gifLoops = $0 }
            ))
            motionBlurRow
            InterfaceToggleRow("Scale Retina to 1x", isOn: $delivery.scalesRetinaToOne)
            InterfaceToggleRow("Optimize", isOn: $delivery.optimizesGIF)
                .help("Combine identical frames. GIF exports contain no audio.")
        }
    }

    private var resolutionRow: some View {
        RecordingExportResolutionControls(settings: $settings, canvasSize: canvasSize)
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
        guard delivery.format == .gif || settings.resolution != .custom || settings.hasValidCustomResolution else { return }
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

struct RecordingExportResolutionControls: View {
    @Binding var settings: VideoCompressionSettings
    var canvasSize: CGSize?

    var body: some View {
        InterfacePickerRow("Resolution", selection: Binding(
            get: { settings.resolution },
            set: { resolution in
                settings.resolution = resolution
                settings.resolutionUsesLongestEdge = true
                if let canvasSize { settings.refitCustomResolution(to: canvasSize) }
            }
        )) {
            ForEach(VideoCompressionResolution.allCases) { resolution in
                Text(resolution.rawValue).tag(resolution)
            }
        }
        if settings.resolution == .custom {
            InterfaceRow("Width") {
                InterfaceValueWithUnitField("Width", value: dimensionBinding(width: true), unit: "px", range: 2...8192)
            }
            InterfaceRow("Height") {
                InterfaceValueWithUnitField("Height", value: dimensionBinding(width: false), unit: "px", range: 2...8192)
            }
            if !settings.hasValidCustomResolution {
                Text("Enter even dimensions between 2 and 8192 pixels.")
            }
        }
    }

    private func dimensionBinding(width: Bool) -> Binding<Int> {
        Binding(
            get: { width ? settings.effectiveCustomWidth : settings.effectiveCustomHeight },
            set: { value in
                if width { settings.customWidth = value } else { settings.customHeight = value }
                if let canvasSize, canvasSize.width.isFinite, canvasSize.height.isFinite,
                   canvasSize.width > 0, canvasSize.height > 0 {
                    let ratio = canvasSize.width / canvasSize.height
                    let other = width ? CGFloat(value) / ratio : CGFloat(value) * ratio
                    let evenOther = max(2, Int((other / 2).rounded()) * 2)
                    if width { settings.customHeight = evenOther } else { settings.customWidth = evenOther }
                }
                AppLog.event("recording", "export_custom_resolution_changed", fields: [
                    "width": String(settings.effectiveCustomWidth), "height": String(settings.effectiveCustomHeight)
                ])
            }
        )
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
