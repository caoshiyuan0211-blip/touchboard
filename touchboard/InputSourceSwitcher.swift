import AppKit
import Carbon

/// Switches back to the previous input source (e.g. ABC ⇄ Pinyin) by pressing the system shortcut
/// "Select the previous input source" (⌃Space by default). Going through the shortcut lets macOS
/// switch properly, so input methods like Pinyin really activate in the focused text field.
enum InputSourceSwitcher {
    /// ID of "Select the previous input source" in System Settings › Keyboard Shortcuts.
    private static let previousSourceHotKeyID = "60"

    static func switchToPrevious() {
        let shortcut = currentShortcut() ?? (keyCode: CGKeyCode(49), flags: CGEventFlags.maskControl)
        press(keyCode: shortcut.keyCode, flags: shortcut.flags)
    }

    /// Reads the user's current shortcut, in case they changed it from ⌃Space.
    /// Returns nil (so ⌃Space is used) if it can't be read or the shortcut is turned off.
    private static func currentShortcut() -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                      "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = hotKeys[previousSourceHotKeyID] as? [String: Any],
              (entry["enabled"] as? Bool) ?? true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int],
              parameters.count >= 3,
              parameters[1] != 65535 else { return nil }
        return (CGKeyCode(parameters[1]), CGEventFlags(rawValue: UInt64(parameters[2])))
    }

    /// Presses a shortcut, including the modifier keys themselves, so the system hotkey fires.
    private static func press(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let modifierKeys: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
            (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55),
        ].filter { flags.contains($0.flag) }

        func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }

        var held: CGEventFlags = []
        for modifier in modifierKeys {
            held.insert(modifier.flag)
            post(modifier.keyCode, down: true, flags: held)
        }
        post(keyCode, down: true, flags: flags)
        post(keyCode, down: false, flags: flags)
        for modifier in modifierKeys.reversed() {
            held.remove(modifier.flag)
            post(modifier.keyCode, down: false, flags: held)
        }
    }
}
