import AppKit
import SwiftUI

/// Finger position and key highlights. These change up to ~100 times a second while typing, so they
/// live apart from the controller: only the keyboard view watches them, not the status window or menu bar.
@MainActor
final class KeyboardLiveState: ObservableObject {
    @Published fileprivate(set) var fingerPoint: CGPoint?
    @Published fileprivate(set) var hoveredKeyID: String?
    @Published fileprivate(set) var pressedKeyID: String?
}

/// Drives the virtual keyboard:
/// - 5-finger swipe down on the trackpad opens / closes it
/// - one finger moves the pointer over the keys
/// - lifting the finger types the key under it
@MainActor
final class TouchKeyboardController: ObservableObject {
    /// How far down (fraction of trackpad height) 5 fingers must travel to count as a swipe.
    static let swipeDistance: Double = 0.15
    /// Allowed keyboard widths (points) for the size setting.
    static let widthRange: ClosedRange<Double> = 360...1000
    private static let widthDefaultsKey = "keyboardWidth"
    /// Allowed keyboard opacities for the transparency setting (1 = solid).
    static let opacityRange: ClosedRange<Double> = 0.2...1
    private static let opacityDefaultsKey = "keyboardOpacity"

    /// How see-through the floating keyboard is, saved between launches.
    @Published var keyboardOpacity: Double {
        didSet {
            UserDefaults.standard.set(keyboardOpacity, forKey: Self.opacityDefaultsKey)
            panel?.alphaValue = CGFloat(keyboardOpacity)
        }
    }

    /// Width of the floating keyboard, saved between launches.
    @Published var keyboardWidth: Double {
        didSet {
            UserDefaults.standard.set(keyboardWidth, forKey: Self.widthDefaultsKey)
            panel?.applySize(keyboardWidth: keyboardWidth)
        }
    }

    @Published private(set) var isActive = false {
        didSet { trackpadFrameGate.setKeyboardOpen(isActive) }
    }
    @Published private(set) var trackpadFound = false
    @Published private(set) var accessibilityGranted = AccessibilityPermission.isGranted

    let live = KeyboardLiveState()

    private let monitor = MultitouchMonitor.shared
    private let pointerBlocker = PointerBlocker()
    private var panel: KeyboardPanel?
    private var permissionTimer: Timer?

    // Which trackpad we are listening to (if more than one is connected).
    private var currentDevice: Int?
    private var currentDeviceHasTouches = false

    // 5-finger swipe tracking
    private var swipeStartY: Double?
    private var waitingForAllFingersUp = false

    // The finger currently pointing at a key.
    private var trackedFingerID: Int?

    /// The last app other than Touchboard that was in front: the app you're typing into.
    private var targetApp: NSRunningApplication?

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.widthDefaultsKey)
        keyboardWidth = saved > 0 ? min(max(saved, Self.widthRange.lowerBound), Self.widthRange.upperBound) : 520
        let savedOpacity = UserDefaults.standard.double(forKey: Self.opacityDefaultsKey)
        keyboardOpacity = savedOpacity > 0 ? min(max(savedOpacity, Self.opacityRange.lowerBound), 1) : 1

        monitor.onFrame = { [weak self] device, contacts in
            self?.handleFrame(device: device, contacts: contacts)
        }
        trackpadFound = monitor.start()

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let granted = AccessibilityPermission.isGranted
                if granted != self.accessibilityGranted { self.accessibilityGranted = granted }
            }
        }
        if !accessibilityGranted { AccessibilityPermission.request() }

        if let front = NSWorkspace.shared.frontmostApplication, front != .current { targetApp = front }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != .current else { return }
            MainActor.assumeIsolated { self?.targetApp = app }
        }
    }

    /// If Touchboard itself is in front (e.g. you clicked Show Keyboard), typed keys would land in
    /// Touchboard instead of your text box. This brings the app you were typing in back to the front.
    /// Returns true if it had to switch apps.
    @discardableResult
    private func returnFocusToTargetApp() -> Bool {
        guard NSApp.isActive, let app = targetApp, !app.isTerminated else { return false }
        app.activate()
        return true
    }

    // MARK: - Open / close

    func toggle() {
        isActive ? close() : open()
    }

    func open() {
        guard !isActive else { return }
        isActive = true
        cancelFinger()
        if panel == nil { panel = KeyboardPanel(controller: self) }
        panel?.showAtBottomOfScreen()
        pointerBlocker.start()
        returnFocusToTargetApp()
    }

    func close() {
        guard isActive else { return }
        isActive = false
        pointerBlocker.stop()
        panel?.orderOut(nil)
        cancelFinger()
    }

    // MARK: - Trackpad frames

    private func handleFrame(device: Int, contacts: [TrackpadContact]) {
        // With several trackpads, follow the one the user is touching.
        if device != currentDevice {
            if contacts.isEmpty || currentDeviceHasTouches { return }
            currentDevice = device
        }
        currentDeviceHasTouches = !contacts.isEmpty

        let count = contacts.count
        if count == 0 {
            if !waitingForAllFingersUp { typeHoveredKey() }
            waitingForAllFingersUp = false
            swipeStartY = nil
            cancelFinger()
            return
        }

        // 5-finger swipe down toggles the keyboard.
        if count >= 5 {
            let centerY = contacts.map(\.y).reduce(0, +) / Double(count)
            if let start = swipeStartY {
                if !waitingForAllFingersUp && start - centerY > Self.swipeDistance {
                    waitingForAllFingersUp = true
                    toggle()
                }
            } else {
                swipeStartY = centerY
            }
            cancelFinger()
            return
        } else if count < 4 {
            swipeStartY = nil // allow a brief drop to 4 fingers mid-swipe
        }

        // Only type with 1–2 fingers, after the toggle gesture's fingers have all lifted.
        // Any extra fingers cancel the pending key so nothing is typed by accident.
        guard isActive, !waitingForAllFingersUp, count <= 2 else {
            cancelFinger()
            return
        }

        if let tracked = trackedFingerID, !contacts.contains(where: { $0.id == tracked }) {
            // The pointing finger lifted while another one stays down: type, then follow the other finger.
            typeHoveredKey()
            cancelFinger()
        }

        let contact = contacts.first { $0.id == trackedFingerID } ?? contacts[0]
        trackedFingerID = contact.id
        let point = KeyboardLayout.point(fromTrackpadX: contact.x, y: contact.y)
        if live.fingerPoint != point { live.fingerPoint = point }
        let keyID = KeyboardLayout.key(at: point)?.id
        if live.hoveredKeyID != keyID { live.hoveredKeyID = keyID }
    }

    /// Forget the current finger without typing anything.
    /// Only touches published values that actually change, so idle frames don't trigger redraws.
    private func cancelFinger() {
        trackedFingerID = nil
        if live.fingerPoint != nil { live.fingerPoint = nil }
        if live.hoveredKeyID != nil { live.hoveredKeyID = nil }
    }

    private func typeHoveredKey() {
        guard isActive, trackedFingerID != nil, let id = live.hoveredKeyID,
              let key = KeyboardLayout.keys.first(where: { $0.id == id }) else { return }
        press(key)
    }

    private func press(_ key: KeyDef) {
        let send: @MainActor @Sendable () -> Void = {
            if key.kind == .switchLanguage {
                InputSourceSwitcher.switchToPrevious()
            } else {
                KeySender.press(key)
            }
        }
        if returnFocusToTargetApp() {
            // Give the other app a moment to come to the front before the key arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: send)
        } else {
            send()
        }
        live.pressedKeyID = key.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let live = self?.live else { return }
                if live.pressedKeyID == key.id { live.pressedKeyID = nil }
            }
        }
    }
}
