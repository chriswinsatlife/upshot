import Foundation

enum RecordingExportAgentGuide {
    static let text = """
    Additional export_video options, saved in export-options.json inside the recording package:
    format: "Video" or "GIF". GIF loops continuously and omits audio.
    gifFrameRate: 10, 15, 20, 25, 30. gifQuality: "Low", "Medium", "High".
    optimizesGIF: true combines identical frames while retaining their elapsed time.
    settings.resolution applies to both GIF and video: "Original", "1080p", "720p", "480p".
    scalesRetinaToOne: true divides the export canvas by the captured pixel scale before applying the resolution limit.
    monoAudio: true downmixes recorded, replacement, and added audio to one channel. export_audio accepts mono: true.
    separateAudioTracks: true retains microphone and system audio as independent movie tracks. Added audio gets its own mixed track. A replacement soundtrack replaces the recorded tracks.
    motionBlurLevel: "Off", "Low", "Medium", "High" selects a zero, quarter, half, or full-frame shutter. This takes precedence over settings.motionBlurEnabled.
    export_video appearance.zoomAnimationStyle: "Smooth" or "Dynamic" selects the zoom spring. Stored in export-appearance.json.
    get_recording returns the current options as exportOptions.
    """
}
