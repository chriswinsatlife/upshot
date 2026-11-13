import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AnnotationWatermarkSourceControls: View {
    @Binding var settings: AnnotationWatermarkSettings
    @State private var importError: String?

    var body: some View {
        HStack {
            Button(settings.imageData == nil ? "Choose Image…" : "Replace Image…", action: chooseImage)
            if settings.imageData != nil {
                Button("Use Text") {
                    settings.imageData = nil
                }
            }
        }
        .alert("Watermark Image Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
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
                NSLog("Annotation watermark image loaded bytes=%ld", data.count)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}
