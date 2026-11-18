import SwiftUI

struct StudioArrowEditingLayer: View {
    @Bindable var model: RecordingStudioModel
    let arrows: [RecordingArrowOverlay]
    let placement: RecordingOverlayPlacement
    let canvasSize: CGSize

    @State private var dragBase: RecordingArrowOverlay?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(arrows) { overlay in
                let reference = placement.referenceRect(for: overlay.coordinateSpace, canvasSize: canvasSize)
                let rect = overlay.rect(in: reference)
                let selected = model.selectedArrowID == overlay.id
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .overlay {
                        if selected {
                            Rectangle()
                                .strokeBorder(Palette.highlight, lineWidth: 1.5)
                                .shadow(color: .black.opacity(0.3), radius: 1)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            StudioRegionHandle(isCorner: true, isHorizontal: false)
                                .offset(x: 11, y: 11)
                                .gesture(gesture(for: overlay, reference: reference, resizing: true))
                        }
                    }
                    .frame(width: max(rect.width, 8), height: max(rect.height, 8))
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture { model.selectArrow(id: overlay.id) }
                    .gesture(gesture(for: overlay, reference: reference, resizing: false))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }

    private func gesture(for overlay: RecordingArrowOverlay, reference: CGRect, resizing: Bool) -> some Gesture {
        DragGesture(minimumDistance: resizing ? 0 : 2, coordinateSpace: .global)
            .onChanged { value in
                if dragBase?.id != overlay.id {
                    dragBase = overlay
                    model.selectArrow(id: overlay.id)
                    model.beginArrowEdit()
                }
                guard let dragBase, reference.width > 0, reference.height > 0 else { return }
                var edited = dragBase
                let dx = value.translation.width / reference.width
                let dy = value.translation.height / reference.height
                if resizing {
                    edited.rect.size.width = min(max(dragBase.rect.width + dx, RecordingRedaction.minimumSide), 1 - dragBase.rect.minX)
                    edited.rect.size.height = min(max(dragBase.rect.height + dy, RecordingRedaction.minimumSide), 1 - dragBase.rect.minY)
                } else {
                    edited.rect = dragBase.rect.offsetBy(dx: dx, dy: dy)
                }
                model.setArrow(edited)
            }
            .onEnded { _ in
                dragBase = nil
                model.endArrowEdit(actionName: resizing ? "Resize Arrow" : "Move Arrow")
            }
    }
}
