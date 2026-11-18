import AppKit
import SwiftUI

/// Floating, blurred window that shows the keyboard without taking focus away from the app you type into.
final class KeyboardPanel: NSPanel {
    private static let cornerRadius: CGFloat = 18

    private let blurView = NSVisualEffectView()
    private let host: NSHostingView<AnyView>

    init(controller: TouchKeyboardController) {
        host = NSHostingView(rootView: AnyView(KeyboardView().environmentObject(controller)))
        let size = Self.panelSize(keyboardWidth: controller.keyboardWidth)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        alphaValue = CGFloat(controller.keyboardOpacity)

        // Blurs whatever is behind the window (desktop, other apps).
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = Self.cornerRadius
        blurView.layer?.masksToBounds = true
        blurView.frame = NSRect(origin: .zero, size: size)
        blurView.autoresizingMask = [.width, .height]

        host.frame = blurView.bounds
        host.autoresizingMask = [.width, .height]
        blurView.addSubview(host)
        contentView = blurView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Window size for a given keyboard width: keyboard + padding.
    static func panelSize(keyboardWidth: Double) -> NSSize {
        let width = CGFloat(keyboardWidth)
        let keyboardHeight = width / KeyboardLayout.width * KeyboardLayout.height
        let padding = KeyboardView.padding(for: width)
        return NSSize(width: width + padding * 2, height: keyboardHeight + padding * 2)
    }

    /// Resize, keeping the keyboard centred at the same bottom edge.
    func applySize(keyboardWidth: Double) {
        let size = Self.panelSize(keyboardWidth: keyboardWidth)
        let old = frame
        setFrame(NSRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height),
                 display: true)
    }

    func showAtBottomOfScreen() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 40))
        }
        orderFrontRegardless()
    }
}

struct KeyboardView: View {
    @EnvironmentObject private var controller: TouchKeyboardController

    static func padding(for width: CGFloat) -> CGFloat { max(8, width * 0.02) }

    var body: some View {
        let padding = Self.padding(for: CGFloat(controller.keyboardWidth))

        GeometryReader { geo in
            let unit = geo.size.width / KeyboardLayout.width
            let gap = max(2, unit * 0.08)
            ZStack(alignment: .topLeading) {
                ForEach(KeyboardLayout.keys) { key in
                    KeyCapView(key: key,
                               unit: unit,
                               isHovered: controller.hoveredKeyID == key.id,
                               isPressed: controller.pressedKeyID == key.id)
                        .frame(width: key.frame.width * unit - gap, height: key.frame.height * unit - gap)
                        .position(x: key.frame.midX * unit, y: key.frame.midY * unit)
                }

                if let p = controller.fingerPoint {
                    let dot = max(10, unit * 0.4)
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .frame(width: dot, height: dot)
                        .shadow(radius: 2)
                        .position(x: p.x * unit, y: p.y * unit)
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(KeyboardLayout.width / KeyboardLayout.height, contentMode: .fit)
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KeyCapView: View {
    let key: KeyDef
    let unit: CGFloat
    let isHovered: Bool
    let isPressed: Bool

    var body: some View {
        let radius = max(3, unit * 0.14)
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(isPressed ? Color.green.opacity(0.85)
                      : isHovered ? Color.accentColor.opacity(0.55)
                      : Color.white.opacity(0.10))

            RoundedRectangle(cornerRadius: radius)
                .stroke(isHovered ? Color.accentColor : Color.white.opacity(0.18), lineWidth: isHovered ? 2 : 1)

            Text(key.label)
                .font(.system(size: unit * (key.label.count > 1 ? 0.28 : 0.4), weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}
