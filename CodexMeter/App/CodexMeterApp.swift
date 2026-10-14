import AppKit
import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var viewModel: UsageViewModel
    @StateObject private var updater = AppUpdater()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)

        let preferencesStore = PreferencesStore()
        let viewModel = UsageViewModel(
            usageService: UsageService(tokenProvider: AuthTokenProvider()),
            preferencesStore: preferencesStore,
            appLauncher: AppLauncher(),
            notificationService: NotificationService(),
            loginItemService: LoginItemService()
        )
        viewModel.start()
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(viewModel: viewModel)
                .environmentObject(updater)
        } label: {
            MenuBarStatusLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CodexMeterCommands(updater: updater, quit: viewModel.quit)
        }

        Window("CodexMeter Settings", id: "settings") {
            SettingsView(viewModel: viewModel)
                .environmentObject(updater)
        }
        .windowResizability(.contentSize)
    }
}
