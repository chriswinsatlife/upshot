import AppKit
import SwiftUI

struct AnnotationEditorWindowLevel: ViewModifier {
    @AppStorage(UpshotPreferences.annotationEditorAlwaysOnTopKey) private var alwaysOnTop = false
    @State private var editorWindow: NSWindow?

    func body(content: Content) -> some View {
        content
            .onWindowChange { window in
                editorWindow = window
                applyWindowLevel()
            }
            .onChange(of: alwaysOnTop) { _, _ in applyWindowLevel() }
            .onDisappear { editorWindow = nil }
    }

    private func applyWindowLevel() {
        guard let editorWindow else { return }
        editorWindow.level = alwaysOnTop ? .floating : .normal
        NSLog("Annotation always on top applied enabled=%@ level=%ld", String(alwaysOnTop), editorWindow.level.rawValue)
    }
}
