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
        guard !UpshotStorage.isRenderingStates else { return }
        guard let editorWindow else { return }
        editorWindow.level = alwaysOnTop ? .floating : .normal
        AppLog.event("annotation", "annotation_always_on_top_applied", fields: ["enabled": String(describing: String(alwaysOnTop)), "level": String(describing: editorWindow.level.rawValue)])
    }
}
