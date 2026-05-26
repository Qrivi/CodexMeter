import AppKit
import SwiftUI

struct CodexMeterCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    let quit: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openSettings()
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
