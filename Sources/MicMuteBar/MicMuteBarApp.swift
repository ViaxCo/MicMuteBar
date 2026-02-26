import AppKit
import SwiftUI

@MainActor
@main
struct MicMuteBarApp: App {
    @State private var preferences: MicMutePreferences
    @State private var controller: MicMuteController
    @State private var launchAtLogin = LaunchAtLoginManager()

    init() {
        let preferences = MicMutePreferences()
        let controller = MicMuteController(preferences: preferences)
        controller.start()

        _preferences = State(initialValue: preferences)
        _controller = State(initialValue: controller)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller, launchAtLogin: launchAtLogin)
        } label: {
            Image(systemName: controller.menuBarSymbolName)
                .help(controller.statusLine)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                controller: controller,
                preferences: preferences,
                launchAtLogin: launchAtLogin
            )
            .frame(width: 520, height: 420)
            .padding()
        }
    }
}
