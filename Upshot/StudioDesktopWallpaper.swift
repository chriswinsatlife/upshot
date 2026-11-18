import AppKit
import AVFoundation
import ColorSync
import CoreGraphics
import Foundation

enum StudioDesktopWallpaper {
    static func snapshot() async throws -> AnnotationCustomWallpaper {
        guard let screen = NSScreen.screens.first(where: {
            ActiveDisplayResolver.displayID(for: $0) == CGMainDisplayID()
        }) ?? NSScreen.main else { throw StudioWallpaperError.desktopUnavailable }
        let displayID = ActiveDisplayResolver.displayID(for: screen) ?? CGMainDisplayID()
        let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        }
        let fallback = NSWorkspace.shared.desktopImageURL(for: screen)
        let directory = AnnotationWallpaperStore.wallpapersDirectory.appendingPathComponent("Desktop Snapshots", isDirectory: true)
        return try await capture(displayID: displayID, displayUUID: displayUUID, fallback: fallback, directory: directory)
    }

    @concurrent
    private static func capture(displayID: CGDirectDisplayID, displayUUID: String?, fallback: URL?, directory: URL) async throws -> AnnotationCustomWallpaper {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let storeURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        var selected: [String: Any]?
        if let data = try? Data(contentsOf: storeURL),
           let store = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            selected = choice(store["AllSpacesAndDisplays"]) ?? choice(store["SystemDefault"])
            if let displays = store["Displays"] as? [String: Any] {
                selected = displayUUID.flatMap { choice(displays[$0]) }
                    ?? choice(displays[String(displayID)]) ?? selected
            }
        }
        let source: URL
        if selected?["Provider"] as? String == "com.apple.wallpaper.choice.aerials" {
            guard let configuration = selected?["Configuration"] as? Data,
                  let values = try PropertyListSerialization.propertyList(from: configuration, format: nil) as? [String: Any],
                  let assetID = values["assetID"] as? String, UUID(uuidString: assetID) != nil else {
                throw StudioWallpaperError.desktopUnavailable
            }
            let modern = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
            let legacy = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer")
            let candidates = [
                modern.appendingPathComponent("videos/\(assetID).mov"),
                legacy.appendingPathComponent("4KSDR240FPS/\(assetID).mov"),
                legacy.appendingPathComponent("4KSDR120FPS/\(assetID).mov"),
                modern.appendingPathComponent("thumbnails/\(assetID).png")
            ]
            guard let aerial = candidates.first(where: {
                guard let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
                return values.isRegularFile == true && (values.fileSize ?? 0) > 0
            }) else { throw StudioWallpaperError.desktopUnavailable }
            source = aerial
        } else if let fallback {
            source = fallback
        } else {
            throw StudioWallpaperError.desktopUnavailable
        }
        let image: CGImage
        if AnnotationCustomWallpaper(url: source).isVideo {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
            generator.appliesPreferredTrackTransform = true
            image = try await generator.image(at: .zero).image
        } else {
            guard let still = StudioWallpaperLibrary.stillImage(at: source) else {
                throw StudioWallpaperError.unreadableMedia
            }
            image = still
        }
        return try StudioWallpaperLibrary.storePNG(image, directory: directory)
    }

    nonisolated private static func choice(_ value: Any?) -> [String: Any]? {
        guard let entry = value as? [String: Any] else { return nil }
        let key = entry["Type"] as? String == "linked" ? "Linked" : "Desktop"
        let settings = entry[key] as? [String: Any]
        let content = settings?["Content"] as? [String: Any] ?? entry["Content"] as? [String: Any]
        return (content?["Choices"] as? [[String: Any]])?.first
    }
}
