import SwiftUI

struct AnnotationEditorSettingsSection: View {
    @AppStorage(UpshotPreferences.annotationStartingToolKey) private var startingTool = AnnotationTool.select.rawValue
    @AppStorage(UpshotPreferences.annotationInverseArrowDirectionKey) private var inverseArrowDirection = false
    @AppStorage(UpshotPreferences.annotationDrawingSmoothingKey) private var drawingSmoothing = UpshotPreferences.annotationDefaultDrawingSmoothing
    @AppStorage(UpshotPreferences.annotationObjectShadowsKey) private var objectShadows = false
    @AppStorage(UpshotPreferences.annotationAutomaticallyExpandCanvasKey) private var automaticallyExpandCanvas = false
    @AppStorage(UpshotPreferences.annotationEditorAlwaysOnTopKey) private var alwaysOnTop = false
    @AppStorage(UpshotPreferences.lowResolutionEditorPreviewKey) private var lowResolutionEditorPreview = true
    @AppStorage(UpshotPreferences.annotationShowColorNamesKey) private var showColorNames = true

    private var smoothDrawing: Binding<Bool> {
        Binding(
            get: { drawingSmoothing > 0 },
            set: { isOn in
                drawingSmoothing = isOn ? UpshotPreferences.annotationDefaultDrawingSmoothing : 0
            }
        )
    }

    var body: some View {
        toolsSection
        windowSection
        accessibilitySectionWithChangeLog
    }

    private var accessibilitySectionWithChangeLog: some View {
        accessibilitySectionWithToolChangeLog
            .onChange(of: alwaysOnTop) { _, value in log("always_on_top", String(value)) }
            .onChange(of: lowResolutionEditorPreview) { _, value in log("low_resolution_preview", String(value)) }
            .onChange(of: showColorNames) { _, value in log("show_color_names", String(value)) }
    }

    private var accessibilitySectionWithToolChangeLog: some View {
        accessibilitySection
            .onChange(of: startingTool) { _, value in log("starting_tool", value) }
            .onChange(of: inverseArrowDirection) { _, value in log("inverse_arrow_direction", String(value)) }
            .onChange(of: drawingSmoothing) { _, value in log("drawing_smoothing", String(describing: value)) }
            .onChange(of: objectShadows) { _, value in log("object_shadows", String(value)) }
            .onChange(of: automaticallyExpandCanvas) { _, value in log("automatically_expand_canvas", String(value)) }
    }

    private var toolsSection: some View {
        InterfaceSection("Tools") {
            InterfacePickerRow("Starting tool", selection: $startingTool) {
                Text("Last Used").tag(UpshotPreferences.startingToolLastUsed)
                Divider()
                ForEach(AnnotationTool.allCases) { tool in
                    Text(tool.title).tag(tool.rawValue)
                }
            }
            InterfaceToggleRow(
                "Inverse arrow direction",
                detail: "Hold ⌥ while drawing to switch direction.",
                isOn: $inverseArrowDirection
            )
            InterfaceToggleRow("Smooth drawing", isOn: smoothDrawing)
            InterfaceToggleRow("Draw shadows on annotations", isOn: $objectShadows)
            InterfaceToggleRow("Automatically expand canvas", isOn: $automaticallyExpandCanvas)
        }
    }

    private var windowSection: some View {
        InterfaceSection("Window") {
            InterfaceToggleRow("Always on top", isOn: $alwaysOnTop)
            InterfacePickerRow("Preview quality", selection: $lowResolutionEditorPreview) {
                Text("Full Resolution").tag(false)
                Text("Reduced Resolution").tag(true)
            }
        }
    }

    private var accessibilitySection: some View {
        InterfaceSection("Accessibility") {
            InterfaceToggleRow("Show color names", isOn: $showColorNames)
        }
    }

    private func log(_ setting: String, _ value: String) {
        AppLog.event("settings", "annotate_settings_changed", fields: ["setting": setting, "value": value])
    }
}
