import Carbon.HIToolbox
import Foundation

extension StateRenderFixtures {
    static let allInOneShortcut = HotkeyShortcut(modifiers: [.command, .shift], keyCode: Int(kVK_ANSI_5))

    func shortcutSettingsModel(customizesAllInOne: Bool = false) -> CaptureHotkeySettingsModel {
        precondition(UpshotStorage.isRenderingStates)
        let assignments: [(CaptureHotkeyAction, HotkeyShortcut.Modifiers, Int)] = [
            (.fullscreen, [.option], kVK_ANSI_1),
            (.window, [.option], kVK_ANSI_2),
            (.area, [.option], kVK_ANSI_3),
            (.screenRecording, [.option], kVK_ANSI_4),
            (.textCapture, [.option], kVK_ANSI_5),
            (.recordingToggle, [.control, .option], kVK_ANSI_R),
            (.captureHistory, [.control, .option], kVK_ANSI_H),
            (.library, [.control, .option], kVK_ANSI_L)
        ]
        for (action, modifiers, keyCode) in assignments {
            CaptureHotkeyPreferences.saveShortcut(HotkeyShortcut(modifiers: modifiers, keyCode: keyCode), for: action)
        }
        if customizesAllInOne {
            CaptureHotkeyPreferences.saveShortcut(HotkeyShortcut(modifiers: [.control, .shift], keyCode: Int(kVK_ANSI_5)), for: .allInOne)
        }
        return CaptureHotkeySettingsModel()
    }
}
