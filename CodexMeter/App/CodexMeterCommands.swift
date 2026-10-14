import AppKit
import SwiftUI

struct CodexMeterCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let updater: AppUpdater
    let quit: () -> Void

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton()
                .environmentObject(updater)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Quit CodexMeter", action: quit)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
