import AppKit
import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var viewModel: UsageViewModel

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
        } label: {
            MenuBarStatusLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CodexMeterCommands(quit: viewModel.quit)
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
