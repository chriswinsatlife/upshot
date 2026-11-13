import Foundation

enum RecordingExportAgentGuide {
    static let text = """
    Additional export_video options, saved in export-options.json inside the recording package:
    format: "Video" or "GIF". GIF loops continuously and omits audio.
    gifFrameRate: 10, 15, 20, 25, 30. gifQuality: "Low", "Medium", "High".
    optimizesGIF: true combines identical frames while retaining their elapsed time.
    settings.resolution applies to both GIF and video: "Original", "1080p", "720p", "480p".
    get_recording returns the current options as exportOptions.
    """
}
