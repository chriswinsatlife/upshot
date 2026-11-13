import AppKit
import SwiftUI

private enum AnnotationBackgroundFillLibrary: CaseIterable, Hashable {
    case color
    case gradient
    case wallpaper

    var title: String {
        switch self {
        case .color: "Color"
        case .gradient: "Gradient"
        case .wallpaper: "Wallpaper"
        }
    }
}

struct AnnotationFrameInspector: View {
    @Binding var settings: AnnotationBackgroundSettings
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    let onEditorAction: () -> Void
    let onPickWallpaper: () -> Void
    let onPreview: (AnnotationBackgroundStyle, Bool) -> Void
    let onEndPreview: () -> Void

    var body: some View {
        InterfaceRow("Background") {
            AnnotationBackgroundPickerButton(
                style: $settings.style,
                rememberedWallpaper: settings.customWallpaper,
                wallpaperStore: wallpaperStore,
                onEditorAction: onEditorAction,
                onPickWallpaper: onPickWallpaper,
                onSelectWallpaper: { settings.customWallpaper = $0 },
                onPreview: onPreview,
                onEndPreview: onEndPreview
            )
        }

        if settings.requiresCanvasLayout {
            AnnotationInspectorSliderRow("Padding", value: $settings.padding, range: 0.04...0.45, format: .percent())
            AnnotationInspectorSliderRow("Corners", value: $settings.cornerRadius, range: 0...0.12, format: .percent())
            AnnotationInspectorSliderRow("Shadow", value: $settings.shadow, range: 0...1, format: .percent())

            InterfacePickerRow("Shadow style", selection: Binding(
                get: { settings.shadowStyle },
                set: { style in
                    onEditorAction()
                    settings.shadowStyle = style
                }
            )) {
                ForEach(AnnotationShadowStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }

            InterfaceRow("Alignment") {
                AlignmentPositionPicker(
                    alignment: $settings.alignment,
                    isEnabled: !settings.camera.hasEffect,
                    onEditorAction: onEditorAction
                )
            }
            .padding(.vertical, Space.xxs)
        }
    }
}

extension AnnotationBackgroundStyle {
    var displayTitle: String {
        switch self {
        case .none: "None"
        case .solid(let color): color.title
        case .gradient(let gradient): gradient.title
        case .customWallpaper(let wallpaper): wallpaper.title
        }
    }
}

struct BackgroundSwatch: View {
    let style: AnnotationBackgroundStyle

    var body: some View {
        switch style {
        case .none:
            Rectangle()
                .fill(Palette.controlFill)
                .overlay {
                    Image(systemName: "slash.circle")
                        .font(.system(size: IconSize.disclosureChevron, weight: .medium))
                        .foregroundStyle(Palette.tertiaryLabel)
                }
        case .solid(let color):
            Rectangle().fill(color.color)
        case .gradient(let gradient):
            Rectangle().fill(LinearGradient(
                colors: gradient.colors.map(\.color),
                startPoint: gradient.startPoint,
                endPoint: gradient.endPoint
            ))
        case .customWallpaper(let wallpaper):
            AnnotationCustomWallpaperPreview(wallpaper: wallpaper, maxPixelSize: 320)
        }
    }
}

struct AnnotationBackgroundPickerButton: View {
    @Binding var style: AnnotationBackgroundStyle
    let rememberedWallpaper: AnnotationCustomWallpaper?
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    let onEditorAction: () -> Void
    let onPickWallpaper: () -> Void
    let onSelectWallpaper: (AnnotationCustomWallpaper) -> Void
    let onPreview: (AnnotationBackgroundStyle, Bool) -> Void
    let onEndPreview: () -> Void

    static let swatchSize = CGSize(width: 20, height: 14)
    static let titleMaximumWidth: CGFloat = 110

    @State private var isPickerPresented = false

    var body: some View {
        Button {
            onEditorAction()
            isPickerPresented = true
        } label: {
            HStack(spacing: InterfaceMetrics.actionButtonIconToLabelSpacing) {
                BackgroundSwatch(style: style)
                    .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sidebarIconTile, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.sidebarIconTile, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 0.5)
                    }
                Text(style.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: Self.titleMaximumWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.interfaceAction)
        .help("Choose a background")
        .accessibilityLabel("Background")
        .accessibilityValue(style.displayTitle)
        .popover(isPresented: $isPickerPresented, arrowEdge: .leading) {
            BackgroundPickerPopover(
                style: $style,
                rememberedWallpaper: rememberedWallpaper,
                wallpaperStore: wallpaperStore,
                onPickWallpaper: {
                    isPickerPresented = false
                    onPickWallpaper()
                },
                onSelectWallpaper: onSelectWallpaper,
                onPreview: onPreview,
                onEndPreview: onEndPreview
            )
        }
    }
}

struct InspectorBackgroundRow: View {
    @Binding var style: AnnotationBackgroundStyle
    var rememberedWallpaper: AnnotationCustomWallpaper? = nil
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    var onEditorAction: () -> Void = {}
    let onPickWallpaper: () -> Void
    var onSelectWallpaper: (AnnotationCustomWallpaper) -> Void = { _ in }
    let onPreview: (AnnotationBackgroundStyle, Bool) -> Void
    let onEndPreview: () -> Void

    @State private var isPickerPresented = false
    @State private var isHovering = false

    var body: some View {
        Button {
            onEditorAction()
            isPickerPresented = true
        } label: {
            HStack(spacing: 8) {
                BackgroundSwatch(style: style)
                    .frame(width: 26, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    }

                Text(style.displayTitle)
                    .font(.inspectorValue)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inspectorField()
            .overlay {
                if isHovering || isPickerPresented {
                    RoundedRectangle(cornerRadius: InspectorMetrics.fieldRadius, style: .continuous)
                        .fill(InspectorControlPalette.hoverFill)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Choose a background")
        .accessibilityLabel("Background")
        .accessibilityValue(style.displayTitle)
        .popover(isPresented: $isPickerPresented, arrowEdge: .leading) {
            BackgroundPickerPopover(
                style: $style,
                rememberedWallpaper: rememberedWallpaper,
                wallpaperStore: wallpaperStore,
                onPickWallpaper: {
                    isPickerPresented = false
                    onPickWallpaper()
                },
                onSelectWallpaper: onSelectWallpaper,
                onPreview: onPreview,
                onEndPreview: onEndPreview
            )
        }
    }
}

struct BackgroundPickerPopover: View {
    @Binding var style: AnnotationBackgroundStyle
    let rememberedWallpaper: AnnotationCustomWallpaper?
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    let onPickWallpaper: () -> Void
    let onSelectWallpaper: (AnnotationCustomWallpaper) -> Void
    let onPreview: (AnnotationBackgroundStyle, Bool) -> Void
    let onEndPreview: () -> Void

    static let size = CGSize(width: 320, height: 520)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                Text("Background")
                    .font(.dsTitle)
                    .foregroundStyle(Palette.label)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if style != .none {
                    Button("None") {
                        onEndPreview()
                        withAnimation(.morphQuickIfAllowed) { style = .none }
                    }
                    .buttonStyle(.interfaceAction)
                    .onHover { onPreview(.none, $0) }
                    .help("Remove the background")
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.l)

            ScrollView(.vertical) {
                InspectorBackgroundFillPicker(
                    style: $style,
                    rememberedWallpaper: rememberedWallpaper,
                    wallpaperStore: wallpaperStore,
                    onEditorAction: {},
                    onPickWallpaper: onPickWallpaper,
                    onSelectWallpaper: onSelectWallpaper,
                    onPreview: onPreview
                )
                .padding(.horizontal, Space.xl)
                .padding(.bottom, Space.xl)
            }
            .scrollEdgeEffectSoftIfAvailable()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.panel)
        .presentationBackground(Palette.panel)
        .onDisappear(perform: onEndPreview)
    }
}

struct InspectorBackgroundFillPicker: View {
    @Binding var style: AnnotationBackgroundStyle
    let rememberedWallpaper: AnnotationCustomWallpaper?
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    let onEditorAction: () -> Void
    let onPickWallpaper: () -> Void
    var onSelectWallpaper: (AnnotationCustomWallpaper) -> Void = { _ in }
    var onPreview: ((AnnotationBackgroundStyle, Bool) -> Void)? = nil

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 8)
    private static let maxVisibleRecentWallpapers = 5
    private static let wallpaperAspectRatio: CGFloat = 1.35
    private let wallpaperColumns = Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3)
    @State private var expandedPackIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            ForEach(AnnotationBackgroundFillLibrary.allCases, id: \.self) { library in
                if library == .wallpaper {
                    unfoldedWallpaperGroup
                } else {
                    group(library.title) {
                        fillPicker(for: library)
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            InterfaceSectionHeader(title)
            content()
        }
    }

    private var customWallpaper: AnnotationCustomWallpaper? {
        if case .customWallpaper(let wallpaper) = style {
            return wallpaper
        }
        return rememberedWallpaper
    }

    @ViewBuilder
    private func fillPicker(for library: AnnotationBackgroundFillLibrary) -> some View {
        switch library {
        case .color:
            LazyVGrid(columns: swatchColumns, spacing: Space.s) {
                ForEach(AnnotationBackgroundColor.plainPresets) { color in
                    InspectorTile(title: color.title, isSelected: style == .solid(color)) {
                        onEditorAction()
                        style = .solid(color)
                    } content: {
                        Rectangle().fill(color.color)
                    }
                    .onHover { onPreview?(.solid(color), $0) }
                }
                InspectorCustomBackgroundColorTile(style: $style, onSelect: onEditorAction)
            }

        case .gradient:
            LazyVGrid(columns: swatchColumns, spacing: Space.s) {
                ForEach(AnnotationBackgroundGradient.presets) { gradient in
                    InspectorTile(title: gradient.title, isSelected: style == .gradient(gradient)) {
                        onEditorAction()
                        style = .gradient(gradient)
                    } content: {
                        Rectangle().fill(LinearGradient(
                            colors: gradient.colors.map(\.color),
                            startPoint: gradient.startPoint,
                            endPoint: gradient.endPoint
                        ))
                    }
                    .onHover { onPreview?(.gradient(gradient), $0) }
                }
            }

        case .wallpaper:
            EmptyView()
        }
    }

    private var unfoldedWallpaperGroup: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            group("Recent") {
                recentWallpaperGrid
            }

            ForEach(AnnotationWallpaperPack.builtIn, id: \.id) { pack in
                VStack(alignment: .leading, spacing: Space.m) {
                    packHeader(pack)
                    packContent(pack, limit: expandedPackIDs.contains(pack.id) ? nil : Self.packPreviewCount)
                }
            }

            UnsplashBackgroundSection(selectedURL: customWallpaper?.url) { url in
                selectWallpaper(AnnotationCustomWallpaper(url: url))
            }
        }
    }

    private static let packPreviewCount = 3

    private func packHeader(_ pack: AnnotationWallpaperPack) -> some View {
        let count = wallpaperStore.wallpapers(for: pack).count
        let isExpanded = expandedPackIDs.contains(pack.id)
        return HStack(spacing: Space.m) {
            InterfaceSectionHeader(pack.title)

            Spacer(minLength: 0)

            if count > Self.packPreviewCount {
                Button(isExpanded ? "Show Less" : "Show All \(count)") {
                    withAnimation(.morphIfAllowed) {
                        if isExpanded {
                            expandedPackIDs.remove(pack.id)
                        } else {
                            expandedPackIDs.insert(pack.id)
                        }
                    }
                }
                .buttonStyle(.interfaceAction)
            }
        }
    }

    @ViewBuilder
    private func packContent(_ pack: AnnotationWallpaperPack, limit: Int? = nil) -> some View {
        let all = wallpaperStore.wallpapers(for: pack)
        let wallpapers = limit.map { Array(all.prefix($0)) } ?? all
        if wallpapers.isEmpty {
            AnnotationWallpaperPackInstallView(
                pack: pack,
                isInstalling: wallpaperStore.isInstalling(pack),
                errorMessage: wallpaperStore.errorMessage(for: pack)
            ) {
                Task { await wallpaperStore.installPack(pack) }
            }
        } else {
            wallpaperGrid(wallpapers)
        }

        AnnotationWallpaperCreditView(pack: pack)
    }

    private var visibleRecentWallpapers: [AnnotationCustomWallpaper] {
        var wallpapers = wallpaperStore.recentWallpapers
        if let customWallpaper, wallpaperStore.isAvailable(customWallpaper) {
            let selectedURL = customWallpaper.url.standardizedFileURL
            if let selectedIndex = wallpapers.firstIndex(where: {
                $0.url.standardizedFileURL == selectedURL
            }) {
                if selectedIndex >= Self.maxVisibleRecentWallpapers {
                    wallpapers.remove(at: selectedIndex)
                    wallpapers.insert(customWallpaper, at: 0)
                }
            } else {
                wallpapers.insert(customWallpaper, at: 0)
            }
        }
        return Array(wallpapers.prefix(Self.maxVisibleRecentWallpapers))
    }

    private var recentWallpaperGrid: some View {
        LazyVGrid(columns: wallpaperColumns, spacing: Space.m) {
            wallpaperTiles(visibleRecentWallpapers)

            AnnotationAddWallpaperTile(aspectRatio: Self.wallpaperAspectRatio) {
                onEditorAction()
                onPickWallpaper()
            }
            .help("Choose wallpaper")
        }
    }

    @ViewBuilder
    private func wallpaperGrid(_ wallpapers: [AnnotationCustomWallpaper]) -> some View {
        LazyVGrid(columns: wallpaperColumns, spacing: Space.m) {
            wallpaperTiles(wallpapers)
        }
    }

    @ViewBuilder
    private func wallpaperTiles(_ wallpapers: [AnnotationCustomWallpaper]) -> some View {
        ForEach(wallpapers) { wallpaper in
            InspectorTile(
                title: wallpaper.title,
                aspectRatio: Self.wallpaperAspectRatio,
                isSelected: isSelectedWallpaper(wallpaper)
            ) {
                selectWallpaper(wallpaper)
            } content: {
                AnnotationCustomWallpaperPreview(wallpaper: wallpaper)
            }
            .onHover { onPreview?(.customWallpaper(wallpaper), $0) }
        }
    }

    private func selectWallpaper(_ wallpaper: AnnotationCustomWallpaper) {
        onEditorAction()
        wallpaperStore.addRecentWallpaper(wallpaper.url)
        onSelectWallpaper(wallpaper)
        style = .customWallpaper(wallpaper)
    }

    private func isSelectedWallpaper(_ wallpaper: AnnotationCustomWallpaper) -> Bool {
        guard case .customWallpaper(let selectedWallpaper) = style else { return false }
        return selectedWallpaper.url.standardizedFileURL == wallpaper.url.standardizedFileURL
    }
}

struct AnnotationWatermarkInspector: View {
    @Binding var settings: AnnotationWatermarkSettings
    let focusedField: FocusState<AnnotationEditorFocusedField?>.Binding
    let onFocusCleared: () -> Void

    static let textFieldMaximumWidth: CGFloat = 170

    private var watermarkSwatch: AnnotationSwatch {
        let color = settings.color
        return AnnotationSwatch.allCases.first {
            abs($0.red - color.red) < 0.002
                && abs($0.green - color.green) < 0.002
                && abs($0.blue - color.blue) < 0.002
        } ?? .custom(from: color.nsColor)
    }

    var body: some View {
        AnnotationWatermarkSourceControls(settings: $settings)

        InterfacePickerRow("Position", selection: $settings.position) {
            ForEach(AnnotationWatermarkPosition.allCases) { position in
                Text(position.title).tag(position)
            }
        }

        InterfaceRow("Text") {
            HStack(spacing: 0) {
                TextField("", text: $settings.text, prompt: Text("Watermark text"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.dsBody)
                    .focused(focusedField, equals: .watermarkText)
                    .onSubmit(finishTextEditing)
                    .accessibilityLabel("Watermark text")
            }
            .interfaceFieldChrome()
            .frame(maxWidth: Self.textFieldMaximumWidth)
            .onClickOutside(enabled: focusedField.wrappedValue == .watermarkText, perform: finishTextEditing)
        }
        .onAppear {
            if !hasWatermarkText { focusedField.wrappedValue = .watermarkText }
        }

        if hasWatermarkText || settings.imageData != nil {
            if settings.imageData != nil {
                AnnotationInspectorSliderRow("Image size", value: $settings.imageWidth, range: 0.02...0.9, format: .percent())
            }
            AnnotationInspectorSliderRow("Density", value: $settings.density, range: 2...10, format: .integer)
            AnnotationInspectorSliderRow("Size", value: $settings.fontSize, range: 8...160, format: .pixels)
            AnnotationInspectorSliderRow("Angle", value: $settings.rotationDegrees, range: -90...90, format: .degrees())
            AnnotationInspectorSliderRow("Opacity", value: $settings.opacity, range: 0...1, format: .percent())

            AnnotationSwatchRow(title: "Color", selectedSwatch: watermarkSwatch) { swatch in
                settings.color = AnnotationWatermarkColor(
                    red: swatch.red,
                    green: swatch.green,
                    blue: swatch.blue
                )
            }
        }
    }

    private var hasWatermarkText: Bool {
        !settings.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func finishTextEditing() {
        focusedField.wrappedValue = nil
        onFocusCleared()
    }
}

private struct AnnotationAddWallpaperTile: View {
    let aspectRatio: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(isHovering ? Palette.secondaryLabel : Palette.strongHairline)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: IconSize.row, weight: .semibold))
                        .foregroundStyle(Palette.secondaryLabel)
                }
                .padding(2.5)
                .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Choose wallpaper")
    }
}

private struct AnnotationWallpaperCreditView: View {
    let pack: AnnotationWallpaperPack

    @State private var isHovering = false

    var body: some View {
        Link(destination: pack.authorURL) {
            HStack(spacing: Space.xxs) {
                Text("Wallpapers by \(pack.authorName)")
                    .underline(isHovering)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: IconSize.disclosureChevron, weight: .semibold))
            }
            .font(.dsCaption)
            .foregroundStyle(Palette.secondaryLabel)
        }
        .buttonStyle(.plain)
        .help("Open \(pack.authorName) on X")
        .onHover { isHovering = $0 }
    }
}

private struct AnnotationWallpaperPackInstallView: View {
    let pack: AnnotationWallpaperPack
    let isInstalling: Bool
    let errorMessage: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Text(pack.subtitle)
                    .font(.dsBody)
                    .foregroundStyle(Palette.secondaryLabel)
                    .lineLimit(1)
                Spacer(minLength: Space.m)
                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: action) {
                    Label("Download", systemImage: "icloud.and.arrow.down")
                }
                .buttonStyle(.interfaceAction)
                .disabled(isInstalling)
                .help("Download \(pack.title)")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.destructiveLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AlignmentPositionPicker: View {
    @Binding var alignment: AnnotationBackgroundAlignment
    let isEnabled: Bool
    let onEditorAction: () -> Void

    private let size: CGFloat = 44
    private let markerSize: CGFloat = 6
    private let cellSize: CGFloat = 12
    private let spacing: CGFloat = Space.xxs

    @State private var hoveredAlignment: AnnotationBackgroundAlignment?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        let columns = Array(
            repeating: GridItem(.fixed(cellSize), spacing: spacing),
            count: 3
        )

        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(AnnotationBackgroundAlignment.allCases) { option in
                Button {
                    onEditorAction()
                    withAnimation(accessibilityReduceMotion ? nil : .snappy(duration: 0.18)) {
                        alignment = option
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(markerFill(for: option))
                        .frame(width: markerSize, height: markerSize)
                        .frame(width: cellSize, height: cellSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .disabled(!isEnabled)
                .help(option.title)
                .onHover { isHovering in
                    guard isEnabled else {
                        hoveredAlignment = nil
                        return
                    }
                    if isHovering {
                        hoveredAlignment = option
                    } else if hoveredAlignment == option {
                        hoveredAlignment = nil
                    }
                }
                .accessibilityLabel("\(option.title) alignment")
                .accessibilityValue(displayedAlignment == option ? "Selected" : "")
                .accessibilityAddTraits(displayedAlignment == option ? .isSelected : [])
            }
        }
        .padding(Space.xxs)
        .frame(width: size, height: size)
        .background(shape.fill(Palette.controlFill))
        .clipShape(shape)
        .opacity(isEnabled ? 1 : 0.46)
        .help(isEnabled ? "Image alignment" : "Reset Camera to use alignment")
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                hoveredAlignment = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image alignment")
    }

    private var displayedAlignment: AnnotationBackgroundAlignment {
        isEnabled ? alignment : .center
    }

    private func markerFill(for option: AnnotationBackgroundAlignment) -> Color {
        if displayedAlignment == option {
            return Palette.label
        }
        if hoveredAlignment == option {
            return Palette.secondaryLabel
        }
        return Palette.tertiaryLabel
    }
}
