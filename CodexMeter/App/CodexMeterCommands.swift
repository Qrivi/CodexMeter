import AppKit
import SwiftUI

struct CodexMeterCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let quit: () -> Void

    var body: some Commands {
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
