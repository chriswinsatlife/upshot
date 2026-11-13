import SwiftUI

struct AllInOneCaptureToolbar: View {
    let selector: AreaCaptureSelection

    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { buttons(AllInOneCaptureMode.allCases) }
                VStack(spacing: 6) {
                    HStack(spacing: 6) { buttons(Array(AllInOneCaptureMode.allCases.prefix(4))) }
                    HStack(spacing: 6) { buttons(Array(AllInOneCaptureMode.allCases.suffix(3))) }
                }
            }
            HStack(spacing: 14) {
                Text(selector.instruction)
                    .font(.system(size: 11))
                Button("Cancel", action: selector.cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25)))
    }

    private func buttons(_ modes: [AllInOneCaptureMode]) -> some View {
        ForEach(modes) { mode in
            Button { selector.chooseMode(mode) } label: {
                Label(mode.title, systemImage: mode.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 7)
                    .background(selector.mode == mode ? .white.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("\(mode.title) (\(mode.shortcut.uppercased()))")
            .accessibilityAddTraits(selector.mode == mode ? [.isSelected] : [])
        }
    }
}
