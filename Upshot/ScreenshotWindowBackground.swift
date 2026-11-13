import AppKit
import CoreGraphics
import Foundation
import ImageIO

nonisolated enum WindowScreenshotBackgroundMode: String, CaseIterable, Identifiable, Sendable {
    case original
    case wallpaper
    case customWallpaper
    case transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Original"
        case .wallpaper: "Desktop wallpaper"
        case .customWallpaper: "Custom wallpaper"
        case .transparent: "Transparent"
        }
    }
}

nonisolated struct ScreenshotWindowBackground: Sendable {
    let mode: WindowScreenshotBackgroundMode
    let wallpaperURL: URL?
    let padding: CGFloat
}

enum ScreenshotWindowBackgroundService {
    static func configuration(displayID: CGDirectDisplayID?) throws -> ScreenshotWindowBackground {
        let mode = UpshotPreferences.screenshotWindowBackground
        let wallpaperURL: URL?
        switch mode {
        case .original, .transparent:
            wallpaperURL = nil
        case .wallpaper:
            let screen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
            } ?? NSScreen.main
            guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
                throw ScreenshotWindowBackgroundError.wallpaperUnavailable
            }
            wallpaperURL = url
        case .customWallpaper:
            let path = UpshotPreferences.screenshotWindowWallpaperPath
            guard !path.isEmpty else { throw ScreenshotWindowBackgroundError.wallpaperUnavailable }
            wallpaperURL = URL(fileURLWithPath: path)
        }
        return ScreenshotWindowBackground(mode: mode, wallpaperURL: wallpaperURL, padding: UpshotPreferences.screenshotWindowPadding)
    }

    nonisolated static func compose(
        image: CGImage,
        configuration: ScreenshotWindowBackground,
        outputScale: CGFloat
    ) throws -> CGImage {
        guard configuration.mode != .original else { return image }
        let padding = Int((configuration.padding * outputScale).rounded())
        let width = image.width + padding * 2
        let height = image.height + padding * 2
        let context = try ScreenshotPixelProcessor.bitmapContext(
            width: width,
            height: height,
            colorSpace: ScreenshotPixelProcessor.colorSpace(for: image)
        )
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        if let wallpaperURL = configuration.wallpaperURL {
            guard let source = CGImageSourceCreateWithURL(wallpaperURL as CFURL, nil),
                  let wallpaper = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height)
                  ] as CFDictionary) else {
                throw ScreenshotWindowBackgroundError.wallpaperUnavailable
            }
            let scale = max(canvas.width / CGFloat(wallpaper.width), canvas.height / CGFloat(wallpaper.height))
            let size = CGSize(width: CGFloat(wallpaper.width) * scale, height: CGFloat(wallpaper.height) * scale)
            context.draw(wallpaper, in: CGRect(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2, width: size.width, height: size.height))
        }
        context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
        guard let output = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        NSLog("Screenshot output: window background applied mode=%@ padding=%d width=%d height=%d", configuration.mode.rawValue, padding, width, height)
        return output
    }
}

nonisolated enum ScreenshotWindowBackgroundError: LocalizedError {
    case wallpaperUnavailable

    var errorDescription: String? {
        "The window screenshot wallpaper could not be loaded. Select an available image in Screenshot Output settings."
    }
}
