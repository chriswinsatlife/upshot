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
    get_recording returns the current options as exportOptions.
    """
}
