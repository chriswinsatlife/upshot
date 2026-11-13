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
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: CGRect(x: 0, y: 0, width: 900, height: 650), style: .normal)!
        view.autostarts = false
        view.shouldCloseWithWindow = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {}
}
