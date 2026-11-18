//
//  touchboardApp.swift
//  touchboard
//
//  Created by yuan cao on 11/17/26.
//

import SwiftUI

@main
struct touchboardApp: App {
    @StateObject private var controller = TouchKeyboardController()

    var body: some Scene {
        Window("Touchboard", id: "main") {
            ContentView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)

        // Keeps the app running (and the 5-finger gesture listening) after the window is closed.
        MenuBarExtra("Touchboard", systemImage: controller.isActive ? "keyboard.fill" : "keyboard") {
            Button(controller.isActive ? "Hide Keyboard" : "Show Keyboard") { controller.toggle() }
            Divider()
            Button("Quit Touchboard") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
