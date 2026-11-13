
import SwiftUI

enum RecordingExportPreferences {
    private static let settingsKey = "recordingExportDefaultSettings"
    private static let hevcDefaultKey = "recordingExportDefaultsMovedToHEVC"

    static var lastSettings: VideoCompressionSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: settingsKey),
                  var decoded = try? JSONDecoder().decode(
                    VideoCompressionSettings.self,
                    from: data
                  ) else {
                return VideoCompressionSettings()
            }
            if !UserDefaults.standard.bool(forKey: hevcDefaultKey) {
                UserDefaults.standard.set(true, forKey: hevcDefaultKey)
                if decoded.codec == .h264 {
                    decoded.codec = .hevc
                    lastSettings = decoded
                }
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: settingsKey)
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
        onConfirm: @escaping (VideoCompressionSettings) -> Void
    ) {
        self.initialSettings = initialSettings
        self.onConfirm = onConfirm
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        InspectorPopover(
            title: "Export Options",
            confirmTitle: "Export",
            onCancel: { dismiss() },
            onConfirm: {
                let confirmed = settings
                RecordingExportPreferences.lastSettings = confirmed
                UpshotPreferences.recordingExtendedExportDefaults = delivery
                dismiss()
                onConfirm(confirmed)
            }
        ) {
            VStack(alignment: .leading, spacing: InspectorMetrics.rowSpacing) {
                segmented("Output", options: RecordingExportFormat.allCases, selection: $delivery.format)
                if delivery.format == .gif {
                    Picker("GIF frame rate", selection: $delivery.gifFrameRate) {
                        ForEach(RecordingGIFFrameRate.allCases, id: \.self) { rate in
                            Text("\(rate.rawValue) fps").tag(rate)
                        }
                    }
                    segmented("GIF quality", options: RecordingGIFQuality.allCases, selection: $delivery.gifQuality)
                    toggle("Optimize GIF", isOn: $delivery.optimizesGIF)
                    InspectorHint("GIF exports loop continuously and contain no audio. Optimization combines identical frames.")
                }
                segmented("Quality", options: VideoCompressionQuality.allCases, selection: $settings.quality)
                segmented("Codec", options: VideoCompressionCodec.allCases, selection: $settings.codec)
                segmented("Resolution", options: VideoCompressionResolution.allCases, selection: $settings.resolution)
                toggle("Scale Retina to 1x", isOn: $delivery.scalesRetinaToOne)
                segmented(
                    "Frame rate",
                    options: VideoExportFrameRate.allCases,
                    selection: Binding(
                        get: { settings.effectiveFrameRate },
                        set: { settings.frameRate = $0 }
                    )
                )

                segmented(
                    "Motion blur",
                    options: RecordingMotionBlurLevel.allCases,
                    selection: Binding(
                        get: { delivery.motionBlurLevel ?? (settings.effectiveMotionBlurEnabled ? .high : .off) },
                        set: { delivery.motionBlurLevel = $0 }
                    )
                )

                segmented(
                    "Format",
                    options: VideoExportContainer.allCases,
                    selection: Binding(
                        get: { settings.effectiveContainer },
                        set: { settings.container = $0 }
                    )
                )

                InspectorHint(formatHint)

                toggle("Mono audio", isOn: $delivery.monoAudio)
                toggle("Separate audio tracks", isOn: $delivery.separateAudioTracks)
                    .help("Keep microphone and system audio as independent tracks. Added audio uses its own mixed track. An imported replacement soundtrack replaces the recorded tracks.")
                toggle("Include audio", isOn: Binding(
                    get: { !settings.removeAudio },
                    set: { settings.removeAudio = !$0 }
                ))
                .padding(.top, 2)
            }
        }
    }

    private var formatHint: String {
        switch settings.effectiveContainer {
        case .mov:
            "Native QuickTime format for Apple apps."
        case .mp4:
            "Plays on more platforms, including Windows, browsers, and Slack."
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        InspectorToggleRow(title, isOn: isOn)
    }

    private func segmented<Option: Hashable & RawRepresentable>(
        _ title: String,
        options: [Option],
        selection: Binding<Option>
    ) -> some View where Option.RawValue == String {
        VStack(alignment: .leading, spacing: InspectorMetrics.groupLabelSpacing) {
            InspectorGroupLabel(title)
            InspectorSegmented(
                options: options,
                isSelected: { $0 == selection.wrappedValue },
                onTap: { selection.wrappedValue = $0 },
                label: {
                    Text($0.rawValue)
                        .font(.inspectorSegment)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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
