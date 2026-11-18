import SwiftUI

struct RecordingExportSettingsSection: View {
    @AppStorage(UpshotPreferences.recordingSystemAudioKey) private var recordsSystemAudio = false
    @State private var delivery = UpshotPreferences.recordingExtendedExportDefaults
    @State private var compression = RecordingExportPreferences.lastSettings

    var body: some View {
        InterfaceSection("Video") {
            InterfacePickerRow("Frame rate", selection: frameRate) {
                ForEach(VideoExportFrameRate.allCases) { rate in
                    Text(rate.rawValue).tag(rate)
                }
            }

            RecordingExportResolutionControls(settings: Binding(
                get: { compression },
                set: { settings in
                    compression = settings
                    RecordingExportPreferences.lastSettings = settings
                    AppLog.event("settings", "recording_export_default_changed", fields: ["option": "resolution", "value": settings.resolution.rawValue])
                }
            ))

            InterfacePickerRow("Encoding", selection: Binding(
                get: { compression.effectiveEncodingMode },
                set: { mode in
                    var stored = RecordingExportPreferences.lastSettings
                    stored.encodingMode = mode
                    compression = stored
                    RecordingExportPreferences.lastSettings = stored
                    AppLog.event("settings", "recording_export_default_changed", fields: ["option": "encodingMode", "value": mode.rawValue])
                }
            )) {
                ForEach(VideoExportEncodingMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }

            InterfaceToggleRow("Scale Retina videos to 1x", isOn: deliveryBinding(\.scalesRetinaToOne, name: "scalesRetinaToOne"))
        }

        InterfaceSection("Audio") {
            InterfaceToggleRow("Record system audio", isOn: $recordsSystemAudio)

            InterfaceToggleRow("Record audio in mono", isOn: deliveryBinding(\.monoAudio, name: "monoAudio"))

            InterfacePickerRow("Audio tracks", selection: deliveryBinding(\.separateAudioTracks, name: "separateAudioTracks")) {
                Text("Single track").tag(false)
                Text("Separate tracks").tag(true)
            }
        }

        InterfaceSection("GIF") {
            InterfacePickerRow("Size", selection: Binding(
                get: { delivery.gifSize },
                set: { deliveryBinding(\.gifSize, name: "gifSize").wrappedValue = $0 }
            )) {
                if delivery.gifSize == nil {
                    Text(compression.resolution.rawValue).tag(nil as RecordingGIFSize?)
                }
                ForEach(RecordingGIFSize.allCases, id: \.self) { size in Text(size.rawValue).tag(Optional(size)) }
            }
            InterfaceToggleRow("Loop", isOn: Binding(
                get: { delivery.effectiveGIFLoops },
                set: { deliveryBinding(\.gifLoops, name: "gifLoops").wrappedValue = $0 }
            ))
            InterfacePickerRow("Frame rate", selection: deliveryBinding(\.gifFrameRate, name: "gifFrameRate")) {
                ForEach(RecordingGIFFrameRate.allCases, id: \.self) { rate in
                    Text("\(rate.rawValue) fps").tag(rate)
                }
            }

            InterfaceToggleRow("Optimize GIFs", isOn: deliveryBinding(\.optimizesGIF, name: "optimizesGIF"))

            InterfaceRow("Quality") {
                InterfaceModeSwitch(
                    "Quality",
                    selection: deliveryBinding(\.gifQuality, name: "gifQuality"),
                    options: RecordingGIFQuality.allCases.map { InterfaceModeSwitchOption(value: $0, title: $0.rawValue) }
                )
            }
        }
        .onAppear {
            delivery = UpshotPreferences.recordingExtendedExportDefaults
            compression = RecordingExportPreferences.lastSettings
        }
    }

    private var frameRate: Binding<VideoExportFrameRate> {
        Binding(
            get: { compression.effectiveFrameRate },
            set: { newValue in
                var stored = RecordingExportPreferences.lastSettings
                stored.frameRate = newValue
                RecordingExportPreferences.lastSettings = stored
                compression = stored
                AppLog.event("settings", "recording_export_default_changed", fields: ["option": "frameRate", "value": newValue.rawValue])
            }
        )
    }

    private func compressionBinding<Value>(_ keyPath: WritableKeyPath<VideoCompressionSettings, Value>, name: String) -> Binding<Value> {
        Binding(
            get: { compression[keyPath: keyPath] },
            set: { newValue in
                var stored = RecordingExportPreferences.lastSettings
                stored[keyPath: keyPath] = newValue
                RecordingExportPreferences.lastSettings = stored
                compression = stored
                AppLog.event("settings", "recording_export_default_changed", fields: ["option": name, "value": String(describing: newValue)])
            }
        )
    }

    private func deliveryBinding<Value>(_ keyPath: WritableKeyPath<RecordingExportDeliveryOptions, Value>, name: String) -> Binding<Value> {
        Binding(
            get: { delivery[keyPath: keyPath] },
            set: { newValue in
                var stored = UpshotPreferences.recordingExtendedExportDefaults
                stored[keyPath: keyPath] = newValue
                UpshotPreferences.recordingExtendedExportDefaults = stored
                delivery = stored
                AppLog.event("settings", "recording_export_default_changed", fields: ["option": name, "value": String(describing: newValue)])
            }
        )
    }
}
