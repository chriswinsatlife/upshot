import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

extension AnnotationCustomWallpaper {
    nonisolated var isVideo: Bool {
        ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(url.pathExtension.lowercased())
    }
}

@MainActor
@Observable
final class StudioWallpaperLibrary {
    static let shared = StudioWallpaperLibrary()
    private static let moviePathsKey = "recordingStudio.wallpaperMoviePaths.v1"
    private static let catalogPathsKey = "recordingStudio.wallpaperCatalogPaths.v1"

    private(set) var movies: [AnnotationCustomWallpaper] = []
    private(set) var isImporting = false
    private(set) var errorMessage: String?
    private(set) var catalogPathsByFile: [String: String] = [:]

    private init() {
        catalogPathsByFile = UpshotStorage.defaults.dictionary(forKey: Self.catalogPathsKey) as? [String: String] ?? [:]
        movies = (UpshotStorage.defaults.stringArray(forKey: Self.moviePathsKey) ?? [])
            .map { AnnotationCustomWallpaper(url: URL(fileURLWithPath: $0)) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func importWallpaper(_ url: URL) async -> AnnotationCustomWallpaper? {
        guard !isImporting else { return nil }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            let directory = AnnotationWallpaperStore.wallpapersDirectory
            let catalogFile = StudioWallpaperCatalog.available.first { $0.wallpaper.url == url }?.wallpaper.url.lastPathComponent
            let wallpaper: AnnotationCustomWallpaper
            if let catalogFile, let path = catalogPathsByFile[catalogFile], FileManager.default.fileExists(atPath: path) {
                wallpaper = AnnotationCustomWallpaper(url: URL(fileURLWithPath: path))
            } else {
                wallpaper = try await Self.copyWallpaper(url, directory: directory)
            }
            if let catalogFile {
                catalogPathsByFile[catalogFile] = wallpaper.url.path
                UpshotStorage.defaults.set(catalogPathsByFile, forKey: Self.catalogPathsKey)
            }
            if wallpaper.isVideo {
                movies.removeAll { $0.url == wallpaper.url }
                movies.insert(wallpaper, at: 0)
                UpshotStorage.defaults.set(movies.map(\.url.path), forKey: Self.moviePathsKey)
            } else {
                AnnotationWallpaperStore.shared.addRecentWallpaper(wallpaper.url)
            }
            AppLog.event("recording", "studio_wallpaper_imported", fields: ["kind": wallpaper.isVideo ? "video" : "image"])
            return wallpaper
        } catch {
            report(error, event: "studio_wallpaper_import_failed")
            return nil
        }
    }

    func desktopWallpaper() async -> AnnotationCustomWallpaper? {
        guard !isImporting else { return nil }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            let wallpaper = try await StudioDesktopWallpaper.snapshot()
            AnnotationWallpaperStore.shared.addRecentWallpaper(wallpaper.url)
            AppLog.event("recording", "studio_desktop_wallpaper_selected")
            return wallpaper
        } catch {
            report(error, event: "studio_desktop_wallpaper_failed")
            return nil
        }
    }

    func remove(_ wallpaper: AnnotationCustomWallpaper) {
        movies.removeAll { $0.url == wallpaper.url }
        UpshotStorage.defaults.set(movies.map(\.url.path), forKey: Self.moviePathsKey)
        AppLog.event("recording", "studio_wallpaper_removed", fields: ["kind": "video"])
    }

    private func report(_ error: any Error, event: String) {
        errorMessage = "The wallpaper could not be loaded. Choose another file or retry."
        AppLog.event("recording", event, fields: ["error": AppLog.error(error)])
    }

    @concurrent
    private static func copyWallpaper(_ url: URL, directory: URL) async throws -> AnnotationCustomWallpaper {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if AnnotationCustomWallpaper(url: url).isVideo {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                  try await asset.loadTracks(withMediaType: .video).first != nil else {
                throw StudioWallpaperError.unreadableMedia
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.maximumSize = CGSize(width: 64, height: 64)
            _ = try await generator.image(at: .zero)
            let targetDirectory = directory.appendingPathComponent("Imported Videos", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let target = targetDirectory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: target)
            return AnnotationCustomWallpaper(url: target)
        }
        guard let image = stillImage(at: url) else { throw StudioWallpaperError.unreadableMedia }
        return try storePNG(image, directory: directory.appendingPathComponent("Imported Images", isDirectory: true),
                            name: url.deletingPathExtension().lastPathComponent)
    }

    nonisolated static func stillImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue),
            kCGImageSourceShouldCache: false
        ] as CFDictionary)
    }

    nonisolated static func storePNG(_ image: CGImage, directory: URL, name: String? = nil) throws -> AnnotationCustomWallpaper {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StudioWallpaperError.unreadableMedia
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw StudioWallpaperError.unreadableMedia }
        let bytes = data as Data
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let destinationDirectory = name == nil ? directory : directory.appendingPathComponent(hash, isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let url = destinationDirectory.appendingPathComponent(name ?? hash).appendingPathExtension("png")
        try bytes.write(to: url, options: .atomic)
        return AnnotationCustomWallpaper(url: url)
    }
}

nonisolated enum StudioWallpaperError: Error {
    case unreadableMedia
    case desktopUnavailable
    case decoderFailed
}

nonisolated enum StudioWallpaperCatalog {
    static let entries: [(file: String, title: String)] = [
        ("golden-gate-day-no-vignette.png", "Golden Gate Day"),
        ("windows-11-bloom.jpg", "Windows 11 Bloom"),
        ("tahoe-light.jpg", "Tahoe Light"), ("tahoe-dark.jpg", "Tahoe Dark"),
        ("macos-hello-black.jpg", "macOS Hello Black"), ("ipad-17-dark.jpg", "iPad 17 Dark"),
        ("recordly-hero.png", "RecordlyBlue"), ("sequoia-blue.jpg", "Sequoia Blue"),
        ("sequoia-blue-orange.jpg", "Sequoia Blue Orange"), ("ventura.jpg", "Ventura"),
        ("sonoma-clouds.jpg", "Sonoma Clouds"), ("sonoma-light.jpg", "Sonoma Light"),
        ("sonoma-dark.jpg", "Sonoma Dark"), ("glassmorphism-4.jpg", "Glassmorphism 4"),
        ("energy-19.jpg", "Energy 19"), ("wallpaper3.jpg", "Wallpaper 3"),
        ("wallpaper4.jpg", "Wallpaper 4"), ("levels.jpg", "Levels"),
        ("wallpaper10.jpg", "Wallpaper 10"), ("ventura-dark.jpg", "Ventura Dark"),
        ("sonoma-evening.jpg", "Sonoma Evening"), ("sonoma-horizon.jpg", "Sonoma Horizon"),
        ("energy-17.jpg", "Energy 17"), ("wispysky.mp4", "Wispy Sky")
    ]

    static var available: [(wallpaper: AnnotationCustomWallpaper, title: String)] {
        entries.compactMap { entry in
            let name = (entry.file as NSString).deletingPathExtension
            let ext = (entry.file as NSString).pathExtension
            guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "StudioWallpapers")
                    ?? Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
            return (AnnotationCustomWallpaper(url: url), entry.title)
        }
    }
}
