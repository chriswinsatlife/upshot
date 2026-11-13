import AppKit

@main
struct MagnifierProbe {
    @MainActor static func main() {
        guard let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 3200, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }
        let strings = ["", "1280 × 800", "X: 99999 Y: -99999 · #FFFFFF", "1920 × 1080 · Live preview unavailable", "日本語 العربية 😀", "0 × 0", String(repeating: "9", count: 200)]
        let appearances: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
        for index in 0..<100_000 {
            autoreleasepool {
                NSAppearance(named: appearances[index % appearances.count])?.performAsCurrentDrawingAppearance {
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                    defer { NSGraphicsContext.restoreGraphicsState() }
                    AreaSelectionMagnifier.draw(in: context, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), point: CGPoint(x: index % 790, y: index % 590), image: nil, samplePosition: CGPoint(x: 0.5, y: 0.5), readout: strings[index % strings.count], showsCrosshair: index % 2 == 0, showsMagnifier: index % 3 == 0)
                }
            }
        }
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { fatalError("bitmap") }
        precondition((0..<(800 * 600 * 4)).contains { bytes[$0] != 0 })
        print("magnifier_probe outcome=completed iterations=100000 appearances=4 readouts=7 bitmap=nonempty")
    }
}
