import Foundation

enum RecordingCameraBubbleAgentEdits {
    static func normalize(_ patch: JSONValue, document: JSONValue, current: RecordingCameraBubbleSettings) throws -> JSONValue {
        guard let style = patch["style"]?.objectValue else { return document }
        do {
            var result = document
            if let raw = style["cameraPreviewFrame"], raw != .null {
                guard let name = raw.stringValue, RecordingCameraPreviewFrame(rawValue: name) != nil else {
                    throw AgentToolError.message("style.cameraPreviewFrame must be legacy, standard, or softBlur.")
                }
            }
            if let raw = style["cameraZoomResponse"], raw != .null {
                guard let name = raw.stringValue, RecordingCameraZoomResponse(rawValue: name) != nil else {
                    throw AgentToolError.message("style.cameraZoomResponse must be progress or magnification.")
                }
            }
            guard let layoutPatch = style["cameraLayout"]?.objectValue else { return result }
            var layout = try result["style"]?["cameraLayout"]?.decode(as: RecordingCameraLayout.self) ?? current.layout
            if let name = layoutPatch["shape"]?.stringValue, let shape = RecordingCameraLayout.Shape(rawValue: name) {
                layout = current.layout
                layout.selectShape(shape)
                let defaults = try JSONValue(encoding: layout)
                var shapeDefaults: [String: JSONValue] = [:]
                for key in ["width", "height", "size"] where layoutPatch[key] == nil {
                    shapeDefaults[key] = defaults[key] ?? .null
                }
                result = result.merging(["style": ["cameraLayout": .object(shapeDefaults)]])
                if style["cameraRoundness"] == nil {
                    result = result.merging(["style": ["cameraRoundness": .number(0.1)]])
                }
            }
            layout = try result["style"]?["cameraLayout"]?.decode(as: RecordingCameraLayout.self) ?? current.layout
            if let name = layoutPatch["positionPreset"]?.stringValue {
                guard let preset = RecordingCameraLayout.PositionPreset(rawValue: name) else {
                    throw AgentToolError.message("style.cameraLayout.positionPreset must match get_editing_guide.")
                }
                if preset != .custom { layout.selectPosition(preset) }
            } else if layoutPatch["positionX"] != nil || layoutPatch["positionY"] != nil {
                var point = current.layout.position
                if let x = layoutPatch["positionX"]?.doubleValue { point.x = x }
                if let y = layoutPatch["positionY"]?.doubleValue { point.y = y }
                layout.setPosition(point)
            } else if let name = layoutPatch["corner"]?.stringValue,
                      let corner = RecordingCameraLayout.Corner(rawValue: name) {
                layout.selectPosition(RecordingCameraLayout.PositionPreset(corner))
            }
            if let width = layoutPatch["width"]?.doubleValue, layoutPatch["height"] == nil,
               layout.shape == .square || layout.shape == .squircle {
                layout.height = min(max(width, 0.1), 1)
            }
            result = result.merging(["style": ["cameraLayout": try JSONValue(encoding: layout)]])
            return result
        } catch {
            AppLog.event("recording", "agent_camera_bubble_update_failed", fields: ["error": AppLog.error(error)])
            throw error
        }
    }
}
