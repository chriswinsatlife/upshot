import AVFoundation
import SwiftUI

struct RecordingCameraCropControl: View {
    private static let coordinateSpaceName = "RecordingCameraCropControl"
    let player: AVPlayer
    let sourceAspect: CGFloat
    @Binding var crop: CGRect
    var mirrored = false

    @FocusState private var focusedHandle: RecordingCameraCropGeometry.Handle?
    @State private var dragStart: CGRect?
    @State private var isHovering = false

    private var visualCrop: CGRect {
        mirrored ? RecordingCameraCropGeometry.mirrored(crop) : RecordingCameraCropGeometry.normalized(crop)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let selection = CGRect(x: visualCrop.minX * size.width, y: visualCrop.minY * size.height,
                                   width: visualCrop.width * size.width, height: visualCrop.height * size.height)
            ZStack(alignment: .topLeading) {
                RecordingCameraPictureView(player: player, sourceAspect: sourceAspect)
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .allowsHitTesting(false)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(selection)
                }
                .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Rectangle()
                    .fill(.clear)
                    .overlay { Rectangle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
                    .contentShape(Rectangle())
                    .frame(width: selection.width, height: selection.height)
                    .offset(x: selection.minX, y: selection.minY)
                    .focusable()
                    .focused($focusedHandle, equals: .move)
                    .accessibilityLabel("Move camera crop")
                    .accessibilityValue("\(Int(visualCrop.width * 100)) percent by \(Int(visualCrop.height * 100)) percent")
                    .gesture(drag(.move, size: size))
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { key in nudge(key, handle: .move) }

                if isHovering || focusedHandle != nil {
                    Path { path in
                        for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                            let x = selection.minX + selection.width * fraction
                            let y = selection.minY + selection.height * fraction
                            path.move(to: CGPoint(x: x, y: selection.minY))
                            path.addLine(to: CGPoint(x: x, y: selection.maxY))
                            path.move(to: CGPoint(x: selection.minX, y: y))
                            path.addLine(to: CGPoint(x: selection.maxX, y: y))
                        }
                    }
                    .stroke(.white.opacity(0.3), lineWidth: 1)
                    .allowsHitTesting(false)
                }

                ForEach(RecordingCameraCropGeometry.Handle.allCases.filter { $0 != .move }, id: \.self) { handle in
                    let point = corner(handle, rect: selection)
                    Rectangle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .focusable()
                        .focused($focusedHandle, equals: handle)
                        .accessibilityLabel("Resize camera crop \(handle.rawValue) corner")
                        .gesture(drag(handle, size: size))
                        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { key in nudge(key, handle: handle) }
                        .position(point)
                }
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
            .onHover { isHovering = $0 }
        }
        .aspectRatio(max(sourceAspect, 0.01), contentMode: .fit)
    }

    private func corner(_ handle: RecordingCameraCropGeometry.Handle, rect: CGRect) -> CGPoint {
        CGPoint(x: handle == .northwest || handle == .southwest ? rect.minX : rect.maxX,
                y: handle == .northwest || handle == .northeast ? rect.minY : rect.maxY)
    }

    private func drag(_ handle: RecordingCameraCropGeometry.Handle, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if dragStart == nil { dragStart = visualCrop }
                focusedHandle = handle
                let delta = CGSize(width: value.translation.width / max(size.width, 1),
                                   height: value.translation.height / max(size.height, 1))
                commit(RecordingCameraCropGeometry.adjusted(dragStart ?? visualCrop, handle: handle, delta: delta))
            }
            .onEnded { _ in
                dragStart = nil
                AppLog.event("recording", "camera_picture_crop_changed", fields: ["input": "drag", "target": handle.rawValue])
            }
    }

    private func nudge(_ key: KeyPress, handle: RecordingCameraCropGeometry.Handle) -> KeyPress.Result {
        let step: CGFloat = key.modifiers.contains(.shift) ? 0.05 : 0.01
        let delta: CGSize
        switch key.key {
        case .leftArrow: delta = CGSize(width: -step, height: 0)
        case .rightArrow: delta = CGSize(width: step, height: 0)
        case .upArrow: delta = CGSize(width: 0, height: -step)
        case .downArrow: delta = CGSize(width: 0, height: step)
        default: return .ignored
        }
        commit(RecordingCameraCropGeometry.adjusted(visualCrop, handle: handle, delta: delta))
        AppLog.event("recording", "camera_picture_crop_changed", fields: ["input": "keyboard", "target": handle.rawValue])
        return .handled
    }

    private func commit(_ visual: CGRect) {
        crop = mirrored ? RecordingCameraCropGeometry.mirrored(visual) : visual
    }
}
