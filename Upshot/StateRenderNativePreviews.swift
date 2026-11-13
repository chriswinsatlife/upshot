import AppKit
import AVFoundation
import QuickLookUI
import SwiftUI

struct StateRenderCameraPreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NSView { CameraRecordingManager.renderPreview(player: player) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct StateRenderQuickLookPreview: NSViewRepresentable {
    let view: QLPreviewView

    init(url: URL) throws {
        guard let view = QLPreviewView(frame: CGRect(x: 0, y: 0, width: 900, height: 650), style: .normal) else {
            throw StateRenderFailure(message: "Quick Look preview could not be initialized")
        }
        view.autostarts = false
        view.shouldCloseWithWindow = true
        view.previewItem = url as NSURL
        self.view = view
    }

    func makeNSView(context: Context) -> QLPreviewView { view }
    func updateNSView(_ nsView: QLPreviewView, context: Context) {}
}
