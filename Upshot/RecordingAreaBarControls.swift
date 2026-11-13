import SwiftUI

struct RecordingAreaBarPill: View {
    @State private var area = RecordingAreaSelectionPresenter.shared

    var body: some View {
        InterfaceSizeFieldsPill(
            width: dimension(isWidth: true) { area.setPixelWidth($0) },
            height: dimension(isWidth: false) { area.setPixelHeight($0) },
            aspectSystemImage: aspectSystemImage
        ) {
            RecordingAreaAspectMenuItems()
        }
        .onSubmit {
            RecordingAreaSelectionPresenter.shared.focusSheet()
        }
        .onExitCommand {
            RecordingAreaSelectionPresenter.shared.focusSheet()
        }
        .help(area.aspect.map { "Locked to \($0.title)" } ?? "Freeform")
    }

    private var aspectSystemImage: String {
        guard let aspect = area.aspect else { return "crop" }
        return aspect.isPortrait ? "rectangle.portrait" : "aspectratio"
    }

    private func dimension(isWidth: Bool, commit: @escaping (Int) -> Void) -> Binding<Int> {
        Binding {
            pixelLength(isWidth: isWidth) ?? 0
        } set: { typed in
            let current = pixelLength(isWidth: isWidth)
            guard typed > 0, typed != current else { return }
            commit(min(typed, 99_999))
        }
    }

    private func pixelLength(isWidth: Bool) -> Int? {
        guard let size = area.selection?.pixelSize else { return nil }
        return isWidth ? size.width : size.height
    }
}

private struct RecordingAreaAspectMenuItems: View {
    @State private var area = RecordingAreaSelectionPresenter.shared

    var body: some View {
        Toggle(isOn: selection(nil)) {
            Text("Freeform")
        }
        if area.aspect == nil, let current = area.currentAspect {
            Button("Lock Current Ratio (\(current.title))") {
                area.lockCurrentRatio()
            }
        }

        Section("Landscape") {
            ForEach(RecordingAreaAspect.landscapePresets, id: \.self, content: item)
        }
        Section {
            item(.square)
        }
        Section("Portrait") {
            ForEach(RecordingAreaAspect.portraitPresets, id: \.self, content: item)
        }

        if let aspect = area.aspect, !RecordingAreaAspect.allPresets.contains(aspect) {
            Section("Custom") {
                item(aspect)
            }
        }

        Divider()

        Button("Swap Width and Height") {
            area.swapOrientation()
        }
        .disabled(!canSwap)
    }

    private var canSwap: Bool {
        area.selection != nil || (area.aspect.map { $0.width != $0.height } ?? false)
    }

    private func item(_ aspect: RecordingAreaAspect) -> some View {
        Toggle(isOn: selection(aspect)) {
            Text(aspect.title)
            if let purpose = aspect.purpose {
                Text(purpose)
            }
        }
    }

    private func selection(_ aspect: RecordingAreaAspect?) -> Binding<Bool> {
        Binding {
            area.aspect == aspect
        } set: { _ in
            area.setAspect(aspect)
        }
    }
}
