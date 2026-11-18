import SwiftUI

struct StudioWallpaperPicker: View {
    @Binding var style: AnnotationBackgroundStyle
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    let onPickWallpaper: () -> Void
    let onSelectWallpaper: (AnnotationCustomWallpaper) -> Void
    let onPreview: ((AnnotationBackgroundStyle, Bool) -> Void)?
    @State private var library = StudioWallpaperLibrary.shared
    @State private var showsVideos = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            InterfaceSectionHeader("Wallpaper")
            Picker("Wallpaper", selection: $showsVideos) {
                Text("Image").tag(false)
                Text("Video").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: showsVideos) { _, value in
                AppLog.event("recording", "studio_wallpaper_library_selected", fields: ["kind": value ? "video" : "image"])
            }

            LazyVGrid(columns: columns, spacing: Space.s) {
                InspectorTile(title: "Add wallpaper", aspectRatio: 4 / 3, isSelected: false, action: onPickWallpaper) {
                    Rectangle().fill(Palette.controlFill)
                        .overlay { Image(systemName: "plus").foregroundStyle(Palette.secondaryLabel) }
                }
                if !showsVideos {
                    InspectorTile(title: "Desktop wallpaper", aspectRatio: 4 / 3, isSelected: isDesktopSelected) {
                        Task {
                            if let wallpaper = await library.desktopWallpaper() { select(wallpaper) }
                        }
                    } content: {
                        Rectangle().fill(Palette.controlFill)
                            .overlay { Image(systemName: "desktopcomputer").foregroundStyle(Palette.secondaryLabel) }
                    }
                }
                ForEach(imported) { wallpaper in
                    tile(wallpaper, title: wallpaper.title, imports: false)
                        .contextMenu {
                            if wallpaper.isVideo {
                                Button("Remove from Library") { library.remove(wallpaper) }
                            }
                        }
                }
                ForEach(StudioWallpaperCatalog.available.filter { $0.wallpaper.isVideo == showsVideos }, id: \.wallpaper.id) { entry in
                    tile(entry.wallpaper, title: entry.title, imports: true)
                }
            }
            .disabled(library.isImporting)
            if library.isImporting { ProgressView().controlSize(.small) }
            if let error = library.errorMessage { InterfaceRowLabel("Wallpaper unavailable", detail: error) }
        }
        .onAppear {
            if case .customWallpaper(let wallpaper) = style { showsVideos = wallpaper.isVideo }
        }
    }

    private var imported: [AnnotationCustomWallpaper] {
        if showsVideos { return library.movies.filter { !isCatalogCopy($0) } }
        var wallpapers = wallpaperStore.recentWallpapers
        if case .customWallpaper(let selected) = style, !selected.isVideo,
           !wallpapers.contains(where: { $0.url == selected.url }) {
            wallpapers.insert(selected, at: 0)
        }
        return wallpapers.filter { !isCatalogCopy($0) }
    }

    private var isDesktopSelected: Bool {
        guard case .customWallpaper(let wallpaper) = style else { return false }
        return wallpaper.url.deletingLastPathComponent().lastPathComponent == "Desktop Snapshots"
    }

    private func isCatalogCopy(_ wallpaper: AnnotationCustomWallpaper) -> Bool {
        library.catalogPathsByFile.values.contains(wallpaper.url.path)
    }

    private func isSelected(_ wallpaper: AnnotationCustomWallpaper) -> Bool {
        guard case .customWallpaper(let selected) = style else { return false }
        return selected == wallpaper || library.catalogPathsByFile[wallpaper.url.lastPathComponent] == selected.url.path
    }

    private func tile(_ wallpaper: AnnotationCustomWallpaper, title: String, imports: Bool) -> some View {
        InspectorTile(title: title, aspectRatio: 4 / 3, isSelected: isSelected(wallpaper)) {
            if imports {
                Task {
                    if let stored = await library.importWallpaper(wallpaper.url) { select(stored) }
                }
            } else { select(wallpaper) }
        } content: {
            if wallpaper.isVideo { StudioWallpaperVideoTile(url: wallpaper.url) }
            else { AnnotationCustomWallpaperPreview(wallpaper: wallpaper) }
        }
        .onHover { onPreview?(.customWallpaper(wallpaper), $0) }
    }

    private func select(_ wallpaper: AnnotationCustomWallpaper) {
        onPreview?(.customWallpaper(wallpaper), false)
        onSelectWallpaper(wallpaper)
        style = .customWallpaper(wallpaper)
        AppLog.event("recording", "studio_wallpaper_selected", fields: ["kind": wallpaper.isVideo ? "video" : "image"])
    }
}
