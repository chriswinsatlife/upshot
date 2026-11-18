import Foundation
import Observation
import SwiftUI

enum RecordingStudioZoomPreferences {
    static let automaticallyAddsZoomsKey = "recordingStudioAutomaticallyAddsZooms"

    static var automaticallyAddsZooms: Bool {
        UpshotStorage.defaults.object(forKey: automaticallyAddsZoomsKey) as? Bool ?? true
    }
}

nonisolated struct RecordingZoomSuggestionFeedback: Identifiable {
    let id = UUID()
    var title: String
    var detail: String?
    var succeeded = false

    init(result: RecordingZoomSuggestionResult, hasTelemetry: Bool, replacedExisting: Bool) {
        switch result.status {
        case .ok:
            let plural = result.cues.count == 1 ? "" : "s"
            title = replacedExisting
                ? "Replaced zooms with \(result.cues.count) interaction-based zoom\(plural)"
                : "Added \(result.cues.count) interaction-based zoom suggestion\(plural)"
            succeeded = true
        case .noTelemetry:
            title = hasTelemetry ? "No usable cursor telemetry" : "No cursor telemetry available"
            detail = hasTelemetry
                ? "The recording does not include enough cursor movement data."
                : "Record a screencast first to generate cursor-based suggestions."
        case .noInteractions:
            title = "No clear interaction moments found"
            detail = "Try a recording with pauses or clicks around important actions."
        case .noSlots:
            title = "No auto-zoom slots available"
            detail = "Detected dwell points overlap existing zoom regions."
        }
    }
}

@Observable
final class RecordingAutomaticZoomState {
    private var checkedSources = Set<URL>()
    private var source: URL?
    private var baseline: Data?
    private(set) var dismissed = false
    private(set) var nudges = true
    var feedback: RecordingZoomSuggestionFeedback?

    func beginAutomaticAttempt(source: URL) -> Bool {
        checkedSources.insert(source).inserted
    }

    func dismiss() {
        dismissed = true
        AppLog.event("recording", "automatic_zoom_prompt_dismissed")
    }

    func observe(source: URL, document: RecordingEditDocument, appearance: RecordingExportAppearance) {
        nonisolated struct Signature: Encodable {
            let document: RecordingEditDocument
            let appearance: RecordingExportAppearance
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let signature = try encoder.encode(Signature(document: document, appearance: appearance))
            if self.source != source {
                self.source = source
                baseline = signature
                dismissed = false
                nudges = true
            } else if baseline != signature {
                nudges = false
            }
        } catch {
            nudges = false
            AppLog.event("recording", "automatic_zoom_baseline_failed", fields: ["error": AppLog.error(error)])
        }
    }
}

struct RecordingAutomaticallyAddsZoomsRow: View {
    @AppStorage(RecordingStudioZoomPreferences.automaticallyAddsZoomsKey) private var enabled = true

    var body: some View {
        InterfaceToggleRow(
            "Automatically add zooms",
            detail: "Add zooms on new recordings. Turning this off won't remove existing zooms.",
            isOn: $enabled
        )
        .onChange(of: enabled) { _, value in
            AppLog.event("settings", "automatic_recording_zooms_changed", fields: ["enabled": String(value)])
        }
    }
}

struct RecordingAutoZoomPrompt: View {
    @Bindable var model: RecordingStudioModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if model.automaticZoomState.nudges && !reduceMotion {
            buttons.keyframeAnimator(initialValue: 0.0) { content, value in
                content.offset(x: value * 3).rotationEffect(.degrees(value * 1.5))
            } keyframes: { _ in
                CubicKeyframe(-1, duration: 0.09, startVelocity: 0, endVelocity: 0)
                CubicKeyframe(1, duration: 0.09, startVelocity: 0, endVelocity: 0)
                CubicKeyframe(-1, duration: 0.09, startVelocity: 0, endVelocity: 0)
                CubicKeyframe(1, duration: 0.09, startVelocity: 0, endVelocity: 0)
                CubicKeyframe(0, duration: 0.12, startVelocity: 0, endVelocity: 0)
                LinearKeyframe(0, duration: 2.52)
            }
        } else {
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: Space.s) {
            Button("Apply auto zooms", systemImage: "pointer.arrow.rays") {
                model.suggestZoomCues()
            }
            Button("Dismiss") {
                model.automaticZoomState.dismiss()
            }
        }
        .buttonStyle(.interfaceAction)
    }
}

struct RecordingZoomSuggestionToast: View {
    @Bindable var state: RecordingAutomaticZoomState

    var body: some View {
        Group {
            if let feedback = state.feedback {
                InterfaceToast(
                    feedback.title,
                    detail: feedback.detail,
                    systemImage: feedback.succeeded ? "checkmark.circle.fill" : "info.circle",
                    tone: feedback.succeeded ? .success : .neutral
                )
            }
        }
        .allowsHitTesting(false)
        .task(id: state.feedback?.id) {
            guard let id = state.feedback?.id else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, state.feedback?.id == id else { return }
            state.feedback = nil
        }
    }
}
