import AppKit
import CoreGraphics
import Foundation
import Observation
import SwiftUI

nonisolated struct RecordingStudioGradient: Codable, Equatable, Hashable {
    var angle: Int
    var colors: [String]

    init(angle: Int, colors: [String]) {
        self.angle = angle
        self.colors = colors
    }

    init?(backgroundGradient: AnnotationBackgroundGradient) {
        guard (2...5).contains(backgroundGradient.colors.count),
              backgroundGradient.colors.allSatisfy({ $0.alpha == 1 }) else { return nil }
        let dx = backgroundGradient.endPoint.x - backgroundGradient.startPoint.x
        let dy = backgroundGradient.endPoint.y - backgroundGradient.startPoint.y
        guard dx.isFinite, dy.isFinite, abs(dx) + abs(dy) > 0.0001 else { return nil }
        angle = Int((atan2(dx, -dy) * 180 / .pi).rounded())
        colors = backgroundGradient.colors.map { color in
            "#" + [color.red, color.green, color.blue].map {
                String(format: "%02x", Int((min(max($0, 0), 1) * 255).rounded()))
            }.joined()
        }
        self = normalized
    }

    static let initial = Self(angle: 135, colors: ["#635bff", "#22d3ee"])
    static let addedColor = "#fb7185"

    var isValid: Bool {
        (2...5).contains(colors.count) && colors.allSatisfy { color in
            color.utf8.count == 7 && color.first == "#" && color.dropFirst().allSatisfy { character in
                "0123456789abcdefABCDEF".contains(character)
            }
        }
    }

    var normalized: Self {
        Self(angle: ((angle % 360) + 360) % 360, colors: colors.map { $0.lowercased() })
    }

    var backgroundGradient: AnnotationBackgroundGradient { gradient(canvasSize: CGSize(width: 1, height: 1)) }

    func gradient(canvasSize: CGSize) -> AnnotationBackgroundGradient {
        let value = normalized
        let radians = CGFloat(value.angle) * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        let width = max(1, canvasSize.width)
        let height = max(1, canvasSize.height)
        let length = abs(width * dx) + abs(height * dy)
        let x = dx * length / width / 2
        let y = dy * length / height / 2
        return AnnotationBackgroundGradient(
            id: "studio-authored-gradient",
            title: "Custom Gradient",
            colors: value.colors.map(Self.color),
            startPoint: UnitPoint(x: 0.5 - x, y: 0.5 - y),
            endPoint: UnitPoint(x: 0.5 + x, y: 0.5 + y)
        )
    }

    static func color(_ hex: String) -> AnnotationBackgroundColor {
        let rgb = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return AnnotationBackgroundColor(hex, title: hex.uppercased(),
            red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255)
    }

    static func hex(_ color: Color) -> String {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        return "#" + components.map { String(format: "%02x", Int((min(max($0, 0), 1) * 255).rounded())) }.joined()
    }
}

extension RecordingStudioStyle {
    nonisolated func resolvedBackground(canvasSize: CGSize, preview: AnnotationBackgroundStyle? = nil) -> AnnotationBackgroundStyle {
        let background = preview ?? self.background
        let authored = authoredGradient ?? {
            guard case .gradient(let gradient) = background,
                  gradient.id == "studio-authored-gradient" else { return nil as RecordingStudioGradient? }
            return RecordingStudioGradient(backgroundGradient: gradient)
        }()
        guard let authoredGradient = authored, authoredGradient.isValid,
              background == .gradient(authoredGradient.backgroundGradient) else { return background }
        return .gradient(authoredGradient.gradient(canvasSize: canvasSize))
    }
}

@Observable
final class RecordingStudioGradientStore {
    private static let key = "recordingStudio.customGradients.v1"
    private(set) var gradients: [RecordingStudioGradient] = []

    init() {
        guard let data = UpshotStorage.defaults.data(forKey: Self.key) else { return }
        do {
            var seen = Set<RecordingStudioGradient>()
            gradients = Array(try JSONDecoder().decode([RecordingStudioGradient].self, from: data)
                .filter(\.isValid).map(\.normalized).filter { seen.insert($0).inserted }.prefix(50))
        } catch {
            AppLog.event("recording", "studio_gradients_load_failed", fields: ["error": AppLog.error(error)])
        }
    }

    func save(_ gradient: RecordingStudioGradient) {
        guard gradient.isValid else {
            AppLog.event("recording", "studio_gradient_save_rejected")
            return
        }
        gradients.removeAll { $0 == gradient.normalized }
        gradients.insert(gradient.normalized, at: 0)
        gradients = Array(gradients.prefix(50))
        persist()
        AppLog.event("recording", "studio_gradient_saved", fields: ["stops": String(gradient.colors.count)])
    }

    func remove(_ gradient: RecordingStudioGradient) {
        gradients.removeAll { $0 == gradient }
        persist()
        AppLog.event("recording", "studio_gradient_removed")
    }

    private func persist() {
        do {
            UpshotStorage.defaults.set(try JSONEncoder().encode(gradients), forKey: Self.key)
        } catch {
            AppLog.event("recording", "studio_gradients_save_failed", fields: ["error": AppLog.error(error)])
        }
    }
}
