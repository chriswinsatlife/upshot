
import AppKit
import CoreGraphics
import SwiftUI

struct AnnotationBackgroundStageFill: View {
    let style: AnnotationBackgroundStyle

    var body: some View {
        switch style {
        case .none:
            Color.clear

        case .solid(let color):
            color.color

        case .gradient(let gradient):
            LinearGradient(
                colors: gradient.colors.map(\.color),
                startPoint: gradient.startPoint,
                endPoint: gradient.endPoint
            )

        case .customWallpaper(let wallpaper):
            AnnotationCustomWallpaperPreview(wallpaper: wallpaper, maxPixelSize: 2048)
        }
    }
}

struct AnnotationWatermarkOverlay: View {
    let settings: AnnotationWatermarkSettings
    let fontScale: CGFloat

    var body: some View {
        Canvas { context, size in
            context.withCGContext { graphics in
                var scaled = settings
                scaled.fontSize *= fontScale
                graphics.translateBy(x: 0, y: size.height)
                graphics.scaleBy(x: 1, y: -1)
                AnnotationBackgroundRenderer.drawWatermark(scaled, in: CGRect(origin: .zero, size: size), context: graphics)
            }
        }

    }
}

struct AnnotationCustomWallpaperPreview: View {
    let wallpaper: AnnotationCustomWallpaper
    var maxPixelSize: CGFloat = 900

    @State private var image: CGImage?
    @State private var isLoading = true
    @State private var didFail = false
    @State private var cacheLease: BoundedCGImageCache.Lease?
    @State private var loadGeneration = UUID()

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else if didFail {
                Color.black
                    .overlay {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
        }
        .onAppear { cacheLease = AnnotationWallpaperPreviewCache.beginUse() }
        .onDisappear {
            loadGeneration = UUID()
            image = nil
            cacheLease = nil
        }
        .task(id: cacheID) {
            await loadImage()
        }
    }

    private var cacheID: String {
        AnnotationWallpaperPreviewCache.cacheID(for: wallpaper.url, maxPixelSize: maxPixelSize)
    }

    @MainActor
    private func loadImage() async {
        guard !Task.isCancelled else { return }
        let generation = UUID()
        loadGeneration = generation
        if cacheLease == nil { cacheLease = AnnotationWallpaperPreviewCache.beginUse() }
        image = nil
        isLoading = true
        didFail = false

        let loadedImage = await AnnotationWallpaperPreviewCache.shared.image(
            for: wallpaper.url,
            maxPixelSize: maxPixelSize
        )

        guard !Task.isCancelled, loadGeneration == generation, cacheLease != nil else { return }
        image = loadedImage
        didFail = loadedImage == nil
        isLoading = false
    }
}
