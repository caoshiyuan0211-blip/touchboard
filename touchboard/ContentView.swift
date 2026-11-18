import SwiftUI

/// Small status window: shows whether the trackpad and permissions are ready, and how to use the keyboard.
struct ContentView: View {
    @EnvironmentObject private var controller: TouchKeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Touchboard", systemImage: "keyboard")
                .font(.title2.bold())

            StatusRow(ok: controller.trackpadFound,
                      text: controller.trackpadFound ? "Trackpad connected" : "No trackpad found")

            HStack {
                StatusRow(ok: controller.accessibilityGranted,
                          text: controller.accessibilityGranted ? "Accessibility allowed" : "Accessibility needed to type into other apps")
                if !controller.accessibilityGranted {
                    Spacer()
                    Button("Open Settings") { AccessibilityPermission.openSettings() }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("How to use").font(.headline)
                Text("1. Click into the app you want to type in.")
                Text("2. Swipe down with 5 fingers on the trackpad to open the keyboard.")
                Text("3. Slide one finger to a key, then lift your finger to type it.")
                Text("4. Swipe down with 5 fingers again to close.")
            }
            .font(.callout)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Keyboard size").font(.headline)
                HStack {
                    Image(systemName: "keyboard").imageScale(.small)
                    Slider(value: $controller.keyboardWidth, in: TouchKeyboardController.widthRange)
                    Image(systemName: "keyboard").imageScale(.large)
                }

                Text("Transparency").font(.headline)
                    .padding(.top, 6)
                HStack {
                    Image(systemName: "circle.dotted")
                    Slider(value: $controller.keyboardOpacity, in: TouchKeyboardController.opacityRange)
                    Image(systemName: "circle.fill")
                }
                Text("Tip: click Show Keyboard to see changes live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(controller.isActive ? "Hide Keyboard" : "Show Keyboard") { controller.toggle() }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct StatusRow: View {
    let ok: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? .green : .orange)
    }
}
