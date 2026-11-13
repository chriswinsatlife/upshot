import AppKit
import Foundation
import ImageIO

nonisolated enum ScreenshotClipboardMode: String, CaseIterable, Identifiable, Sendable {
    case file
    case image
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: "File"
        case .image: "Image"
        case .both: "File and image"
        }
    }
}

enum ScreenshotClipboardService {
    static func copy(
        from url: URL,
        mode: ScreenshotClipboardMode? = nil,
        to pasteboard: NSPasteboard = .general
    ) throws {
        let selectedMode = mode ?? UpshotPreferences.screenshotClipboardMode
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        let item = NSPasteboardItem()
        if selectedMode != .image {
            item.setString(url.absoluteString, forType: .fileURL)
        }
        if selectedMode != .file {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let representation = NSBitmapImageRep(cgImage: image)
            guard let png = representation.representation(using: .png, properties: [:]),
                  let tiff = representation.tiffRepresentation else {
                throw CocoaError(.fileReadCorruptFile)
            }
            item.setData(png, forType: .png)
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw CocoaError(.fileWriteUnknown) }
        AppLog.event("capture", "screenshot_output_clipboard_copied", fields: ["mode": String(describing: selectedMode.rawValue)])
    }
}
