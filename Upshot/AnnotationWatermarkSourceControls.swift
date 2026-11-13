import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AnnotationWatermarkSourceControls: View {
    @Binding var settings: AnnotationWatermarkSettings
    @State private var importError: String?

    var body: some View {
        InterfaceRow("Image") {
            if settings.imageData != nil {
                Button("Use Text") {
                    settings.imageData = nil
                }
                .buttonStyle(.interfaceAction)
            }
            Button(settings.imageData == nil ? "Choose…" : "Replace…", action: chooseImage)
                .buttonStyle(.interfaceAction)
                .help(settings.imageData == nil ? "Choose a watermark image" : "Replace the watermark image")
        }
        .appAlert(item: $importError, alert: { AppAlerts.watermarkImageFailed(message: $0) })
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Watermark Image"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                guard NSImage(data: data) != nil else { throw CocoaError(.fileReadCorruptFile) }
                settings.imageData = data
                settings.position = .bottomRight
                settings.rotationDegrees = 0
                AppLog.event("annotation", "annotation_watermark_image_loaded", fields: ["bytes": String(describing: data.count)])
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
