import SwiftUI

struct StudioToolRail: View {
    let pages: [StudioInspectorPage]
    let highlightedPage: StudioInspectorPage?
    let onSelect: (StudioInspectorPage) -> Void

    var body: some View {
        VStack(spacing: Space.xs) {
            ForEach(pages.filter { $0 != .clip }) { page in
                railButton(page)
            }
            Spacer(minLength: Space.l)
            if pages.contains(.clip) {
                railButton(.clip)
            }
        }
        .padding(Space.s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.panel)
    }

    private func railButton(_ page: StudioInspectorPage) -> some View {
        InterfaceToolbarButton(
            page.title,
            systemImage: page.systemImage,
            isSelected: highlightedPage == page,
            labelPlacement: .hidden
        ) {
            onSelect(page)
        }
    }
}
