import AppKit
import ApplicationServices

/// Types keys into whichever app is in front. Needs Accessibility permission.
enum KeySender {
    static func press(_ key: KeyDef) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: false) else { return }
        // Real arrow-key events carry the Fn and numeric-pad flags; some apps check for them.
        let flags: CGEventFlags = key.kind == .arrow ? [.maskSecondaryFn, .maskNumericPad] : []
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security › Accessibility.
    static func request() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// While the keyboard is open, finger movement on the trackpad should only drive the keyboard:
/// this swallows pointer moves, clicks (including tap-to-click) and scrolling.
final class PointerBlocker {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        let types: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon {
                    let blocker = Unmanaged<PointerBlocker>.fromOpaque(refcon).takeUnretainedValue()
                    if let tap = blocker.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                }
                return Unmanaged.passUnretained(event)
            }
            return nil // drop the event
        }

        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        CGAssociateMouseAndMouseCursorPosition(0)
        return true
    }

    func stop() {
        CGAssociateMouseAndMouseCursorPosition(1)
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }
}
