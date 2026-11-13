import AppKit
import SwiftUI

@MainActor
enum CenteredSymbolImage {
    private static var cache: [String: NSImage] = [:]

    static func image(_ systemName: String, pointSize: CGFloat, canvas: NSSize) -> NSImage {
        let key = "\(systemName)|\(pointSize)|\(canvas.width)x\(canvas.height)"
        if let cached = cache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .medium)
        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            AppLog.event("interface", "symbol_missing", fields: ["symbol": systemName])
            let empty = NSImage(size: canvas)
            empty.isTemplate = true
            return empty
        }
        let scale = min(1, canvas.width / symbol.size.width, canvas.height / symbol.size.height)
        let drawn = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let image = NSImage(size: canvas, flipped: false) { bounds in
            symbol.draw(in: NSRect(x: (bounds.width - drawn.width) / 2, y: (bounds.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height))
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }
}

struct MenuBarItemLabel: View {
    static let iconCanvas = NSSize(width: 18, height: 16)

    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(nsImage: CenteredSymbolImage.image(symbol, pointSize: NSFont.menuFont(ofSize: 0).pointSize, canvas: Self.iconCanvas))
        }
    }
}
