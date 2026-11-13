import Foundation
import Observation

@MainActor
@Observable
final class OverlayCardLayoutStore {
    static let shared = OverlayCardLayoutStore()

    var layout: OverlayCardLayout {
        didSet { persist() }
    }

    private init() {
        layout = Self.load()
    }

    func reset() {
        layout = .default
    }

    private static func load() -> OverlayCardLayout {
        guard
            let data = UpshotStorage.defaults.data(forKey: UpshotPreferences.overlayCardLayoutKey),
            let decoded = try? JSONDecoder().decode(OverlayCardLayout.self, from: data)
        else {
            return .default
        }
        return decoded.normalized()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        UpshotStorage.defaults.set(data, forKey: UpshotPreferences.overlayCardLayoutKey)
    }
}
