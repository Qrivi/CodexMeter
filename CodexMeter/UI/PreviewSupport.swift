import Foundation

#if DEBUG
enum PreviewSupport {
    static let snapshot = UsageSnapshot(
        meters: [UsageMeterViewData(
            id: .primary,
            kind: .rateLimit,
            title: "5 hour limit",
            valueText: "64% remaining",
            resetText: "Resets 2:35 PM (4h 28m)",
            remainingPercent: 64,
            level: .good,
            resetDate: Date(timeIntervalSince1970: 1_778_070_900),
            isAvailable: true,
            compactTitle: "5 hour"
        ),
        UsageMeterViewData(
            id: .secondary,
            kind: .rateLimit,
            title: "Weekly limit",
            valueText: "18% remaining",
            resetText: "Resets May 6, 2026 10:30 AM (1d 0h)",
            remainingPercent: 18,
            level: .critical,
            resetDate: Date(timeIntervalSince1970: 1_778_141_800),
            isAvailable: true,
            compactTitle: "Weekly"
        ),
        UsageMeterViewData(
            id: .credits,
            kind: .credits,
            title: "Credits remaining",
            valueText: "12",
            resetText: nil,
            remainingPercent: nil,
            level: .neutral,
            resetDate: nil,
            isAvailable: true
        )],
        lastUpdated: Date(timeIntervalSince1970: 1_778_054_820),
        warningMessage: nil
    )

    @MainActor
    static func viewModel(snapshot: UsageSnapshot? = nil) -> UsageViewModel {
        let previewSnapshot = snapshot ?? Self.snapshot
        let userDefaults = UserDefaults(suiteName: "CodexMeterPreview-\(UUID().uuidString)")!
        let store = PreferencesStore(userDefaults: userDefaults)
        store.menuBarColorMode = .colorfulWhenLow

        let viewModel = UsageViewModel(
            usageService: PreviewUsageFetcher(snapshot: previewSnapshot),
            preferencesStore: store,
            appLauncher: PreviewAppLauncher(),
            notificationService: PreviewNotificationService(),
            loginItemService: PreviewLoginItemService(),
            wakeNotificationCenter: NotificationCenter()
        )

        viewModel.applyPreviewSnapshot(previewSnapshot)

        return viewModel
    }

    @MainActor
    static func failingViewModel() -> UsageViewModel {
        let viewModel = self.viewModel(snapshot: Self.snapshot)
        viewModel.applyPreviewFailure("Auth token unavailable. Open Codex to refresh it.")
        return viewModel
    }
}

private struct PreviewUsageFetcher: UsageFetching {
    let snapshot: UsageSnapshot

    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        snapshot
    }
}

private struct PreviewAppLauncher: AppLaunching {
    func openUsageDashboard() async -> Bool { true }
    func openCodex() async -> Bool { true }
}

private struct PreviewNotificationService: NotificationScheduling {
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func evaluateNotifications(
        for snapshot: UsageSnapshot,
        settings: [UsageMeterID: MeterPreferences]
    ) async {}
}

private struct PreviewLoginItemService: LoginItemManaging {
    func isEnabled() -> Bool { false }
    func setEnabled(_ isEnabled: Bool) throws {}
}
#endif
