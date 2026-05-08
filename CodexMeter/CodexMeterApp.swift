import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var viewModel: UsageViewModel

    init() {
        let preferencesStore = PreferencesStore()
        let viewModel = UsageViewModel(
            usageService: UsageService(tokenProvider: AuthTokenProvider()),
            preferencesStore: preferencesStore,
            appLauncher: AppLauncher(),
            notificationService: NotificationService()
        )
        viewModel.start()
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(viewModel: viewModel)
        } label: {
            Text(viewModel.statusBarText)
        }
        .menuBarExtraStyle(.menu)
    }
}
