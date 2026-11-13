import AppKit

@MainActor
final class TextCaptureSelection {
    func select() async throws -> CGImage? {
        guard let selection = try await AreaCaptureSelection.shared.select(delaySeconds: UpshotPreferences.captureDelaySeconds) else { return nil }
        return try await ScreenshotManager.shared.image(for: selection, delaySeconds: UpshotPreferences.captureDelaySeconds)
    }
}
