import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

struct RecordingCameraPictureView: NSViewRepresentable {
    let player: AVPlayer
    let sourceAspect: CGFloat
    var crop = RecordingCameraCropGeometry.unit

    func makeNSView(context: Context) -> RecordingCameraPictureContainerView {
        let view = RecordingCameraPictureContainerView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: RecordingCameraPictureContainerView, context: Context) {
        view.playerLayer.player = player
        view.sourceAspect = sourceAspect
        view.crop = crop
        view.needsLayout = true
    }
}

final class RecordingCameraPictureContainerView: NSView {
    let playerLayer = AVPlayerLayer()
    var sourceAspect: CGFloat = 1
    var crop = RecordingCameraCropGeometry.unit

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resize
        layer?.addSublayer(playerLayer)
    }

    convenience init() { self.init(frame: .zero) }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let picture = RecordingCameraCropGeometry.fillRect(
            sourceSize: CGSize(width: sourceAspect, height: 1), destination: bounds, crop: crop
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = CGRect(x: picture.minX, y: bounds.height - picture.maxY,
                                   width: picture.width, height: picture.height)
        CATransaction.commit()
    }
}
