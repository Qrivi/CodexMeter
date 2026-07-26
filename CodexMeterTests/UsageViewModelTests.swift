import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct UsageViewModelTests {
    @MainActor
    @Test
    func launchRefreshPopulatesSnapshot() async throws {
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.success(makeSnapshot())]))

        viewModel.start()
        try await waitUntil { viewModel.loadState == .loaded }

        #expect(viewModel.snapshot?.meter(id: .primary)?.remainingPercent == 64)
        #expect(viewModel.loadState == .loaded)
    }

    @MainActor
    @Test
    func disablesManualRefreshForOneMinuteAfterLatestRefresh() async throws {
        let latestRefresh = Date(timeIntervalSince1970: 1_778_054_820)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot(lastUpdated: latestRefresh))])
        )

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }

        #expect(viewModel.canRefreshNow(at: latestRefresh.addingTimeInterval(59)) == false)
        #expect(viewModel.canRefreshNow(at: latestRefresh.addingTimeInterval(60)) == true)
    }

    @MainActor
    @Test
    func doesNotOverlapRefreshRequests() async throws {
        let tracker = RefreshTracker()
        let service = BlockingUsageFetcher(tracker: tracker, snapshot: makeSnapshot())
        let viewModel = makeViewModel(service: service)

        viewModel.refreshNow()
        viewModel.refreshNow()
        await tracker.waitUntilCalled()

        #expect(await tracker.callCount == 1)
        await tracker.resume()
        try await waitUntil { viewModel.loadState == .loaded }
    }

    @MainActor
    @Test
    func preservesLastGoodDataAfterRefreshFailure() async throws {
        let initialSnapshot = makeSnapshot()
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [
            .success(initialSnapshot),
            .failure(UsageServiceError.network("Offline"))
        ]))

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }
        viewModel.refreshNow()
        try await waitUntil { viewModel.snapshot?.warningMessage == "Offline" }

        #expect(viewModel.snapshot?.meter(id: .primary)?.remainingPercent == initialSnapshot.meter(id: .primary)?.remainingPercent)
        #expect(viewModel.snapshot?.warningMessage == "Offline")
        #expect(viewModel.menuBarText == "Error")
        #expect(viewModel.menuBarTextSegments == [MenuBarLabelSegment(text: "Error", tone: .critical)])
    }

    @MainActor
    @Test
    func showsErrorStatusInMenuBarAfterStaleDataAuthenticationFailure() async throws {
        let initialSnapshot = makeSnapshot()
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [
            .success(initialSnapshot),
            .failure(UsageServiceError.unauthorized)
        ]))

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }
        viewModel.refreshNow()
        try await waitUntil { viewModel.snapshot?.warningMessage == "Auth token unavailable. Open Codex to refresh it." }

        #expect(viewModel.snapshot?.meter(id: .primary)?.remainingPercent == initialSnapshot.meter(id: .primary)?.remainingPercent)
        #expect(viewModel.snapshot?.warningMessage == "Auth token unavailable. Open Codex to refresh it.")
        #expect(viewModel.menuBarText == "Error")
        #expect(viewModel.menuBarTextSegments == [MenuBarLabelSegment(text: "Error", tone: .critical)])
    }

    @MainActor
    @Test
    func showsAuthGuidanceForAuthenticationFailure() async throws {
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.failure(UsageServiceError.unauthorized)]))

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .failed(message: "Auth token unavailable. Open Codex to refresh it.") }

        #expect(viewModel.currentFailureMessage == "Auth token unavailable. Open Codex to refresh it.")
        #expect(viewModel.loadState == .failed(message: "Auth token unavailable. Open Codex to refresh it."))
    }

    @MainActor
    @Test
    func reschedulesPollingWhenIntervalChanges() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.success(makeSnapshot())]), preferencesStore: store)

        let initialVersion = viewModel.pollingScheduleVersion
        viewModel.selectPollingInterval(.minute1)

        #expect(viewModel.pollingInterval == .minute1)
        #expect(store.pollingInterval == .minute1)
        #expect(viewModel.pollingScheduleVersion == initialVersion + 1)
    }

    @MainActor
    @Test
    func updatesMenuBarLabelWhenDisplayModeChanges() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.success(makeSnapshot())]), preferencesStore: store)

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }
        viewModel.selectMenuBarDisplayMode(.credits)

        #expect(viewModel.menuBarTitle == "Credits")
        #expect(viewModel.menuBarText == "12 cr")
    }

    @MainActor
    @Test
    func offersEveryReturnedRateLimitAndDisablesUnavailableWindows() async throws {
        let sparkPrimaryID = UsageMeterID.additional(
            feature: "codex_bengalfox",
            slot: .primary
        )
        let sparkSecondaryID = UsageMeterID.additional(
            feature: "codex_bengalfox",
            slot: .secondary
        )
        let unavailableSecondary = UsageMeterViewData(
            id: .secondary,
            kind: .rateLimit,
            title: "Secondary window",
            valueText: "Unavailable",
            resetText: nil,
            remainingPercent: nil,
            level: .neutral,
            resetDate: nil,
            isAvailable: false
        )
        let sparkPrimary = UsageMeterViewData(
            id: sparkPrimaryID,
            kind: .rateLimit,
            title: "GPT-5.3-Codex-Spark · Weekly limit",
            valueText: "80% remaining",
            resetText: nil,
            remainingPercent: 80,
            level: .good,
            resetDate: nil,
            isAvailable: true,
            compactTitle: "Weekly"
        )
        let sparkSecondary = UsageMeterViewData(
            id: sparkSecondaryID,
            kind: .rateLimit,
            title: "GPT-5.3-Codex-Spark · 5 hour limit",
            valueText: "35% remaining",
            resetText: nil,
            remainingPercent: 35,
            level: .warning,
            resetDate: nil,
            isAvailable: true,
            compactTitle: "5 hour"
        )
        let baseSnapshot = makeSnapshot()
        let snapshot = UsageSnapshot(
            meters: [
                baseSnapshot.meter(id: .primary)!,
                unavailableSecondary,
                sparkPrimary,
                sparkSecondary,
                baseSnapshot.meter(id: .credits)!
            ],
            lastUpdated: baseSnapshot.lastUpdated,
            warningMessage: nil
        )
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(snapshot)])
        )

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }

        #expect(viewModel.menuBarDisplayOptions == [
            .both,
            .primaryRemaining,
            .secondaryRemaining,
            .meter(sparkPrimaryID),
            .meter(sparkSecondaryID),
            .credits
        ])
        #expect(viewModel.menuBarDisplayDividerOptions == [
            .meter(sparkPrimaryID),
            .credits
        ])
        #expect(viewModel.menuBarDisplayTitle(for: .both) == "Main usage limits")
        #expect(viewModel.menuBarDisplayTitle(for: .primaryRemaining) == "5 hour limit")
        #expect(viewModel.menuBarDisplayTitle(for: .secondaryRemaining) == "Secondary window")
        #expect(viewModel.isMenuBarDisplayModeEnabled(.primaryRemaining))
        #expect(viewModel.isMenuBarDisplayModeEnabled(.secondaryRemaining) == false)
        #expect(viewModel.isMenuBarDisplayModeEnabled(.meter(sparkPrimaryID)))
        #expect(viewModel.isMenuBarDisplayModeEnabled(.meter(sparkSecondaryID)))

        viewModel.selectMenuBarDisplayMode(.secondaryRemaining)

        #expect(viewModel.menuBarDisplayMode == .both)

        viewModel.selectMenuBarDisplayMode(.meter(sparkSecondaryID))

        #expect(viewModel.menuBarTitle == "5 hour")
        #expect(viewModel.menuBarText == "35%")
    }

    @MainActor
    @Test
    func fallsBackWhenStoredDynamicMeterDisappears() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let missingMeterID = UsageMeterID.additional(
            feature: "codex_bengalfox",
            slot: .primary
        )
        store.menuBarDisplayMode = .meter(missingMeterID)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store
        )

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }

        #expect(viewModel.menuBarDisplayMode == .both)
        #expect(store.menuBarDisplayMode == .both)
        #expect(viewModel.menuBarDisplayDividerOptions == [.credits])
    }

    @MainActor
    @Test
    func fallsBackWhenStoredMainWindowIsUnavailable() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        store.menuBarDisplayMode = .secondaryRemaining
        let baseSnapshot = makeSnapshot()
        let unavailableSecondary = UsageMeterViewData(
            id: .secondary,
            kind: .rateLimit,
            title: "Secondary window",
            valueText: "Unavailable",
            resetText: nil,
            remainingPercent: nil,
            level: .neutral,
            resetDate: nil,
            isAvailable: false
        )
        let snapshot = UsageSnapshot(
            meters: [
                baseSnapshot.meter(id: .primary)!,
                unavailableSecondary,
                baseSnapshot.meter(id: .credits)!
            ],
            lastUpdated: baseSnapshot.lastUpdated,
            warningMessage: nil
        )
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(snapshot)]),
            preferencesStore: store
        )

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }

        #expect(viewModel.menuBarDisplayMode == .both)
        #expect(store.menuBarDisplayMode == .both)
    }

    @MainActor
    @Test
    func keepsStoredDynamicMeterInPickerWhileInitialRefreshIsPending() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let sparkMeterID = UsageMeterID.additional(
            feature: "codex_bengalfox",
            slot: .primary
        )
        store.menuBarDisplayMode = .meter(sparkMeterID)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store
        )

        #expect(viewModel.menuBarDisplayOptions == [
            .both,
            .primaryRemaining,
            .secondaryRemaining,
            .meter(sparkMeterID),
            .credits
        ])
    }

    @MainActor
    @Test
    func persistsMenuBarColorMode() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot(fiveHourRemaining: 18))]),
            preferencesStore: store
        )

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }
        viewModel.selectMenuBarColorMode(.colorfulWhenLow)

        #expect(viewModel.menuBarColorMode == .colorfulWhenLow)
        #expect(store.menuBarColorMode == .colorfulWhenLow)
        #expect(viewModel.menuBarTextSegments == [
            MenuBarLabelSegment(text: "18%", tone: .critical),
            MenuBarLabelSegment(text: "/", tone: .neutral),
            MenuBarLabelSegment(text: "73%", tone: .neutral)
        ])
    }

    @MainActor
    @Test
    func persistsInAppAppearanceColorModes() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.success(makeSnapshot())]), preferencesStore: store)

        viewModel.selectMeterColorMode(.monochrome)
        viewModel.selectRemainingLabelColorMode(.colorful)

        #expect(viewModel.meterColorMode == .monochrome)
        #expect(viewModel.remainingLabelColorMode == .colorful)
        #expect(store.meterColorMode == .monochrome)
        #expect(store.remainingLabelColorMode == .colorful)
    }

    @MainActor
    @Test
    func hidesOnlyTheSelectedMeterAndPersistsItsSettings() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store
        )

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }
        viewModel.setMeterVisible(false, meterID: .secondary)

        #expect(viewModel.visibleMeters(in: viewModel.snapshot!).map(\.id) == [.primary, .credits])
        #expect(store.meterPreferences[.secondary]?.isVisible == false)
        #expect(viewModel.preferences(for: .primary).isVisible)
    }

    @MainActor
    @Test
    func distinguishesUnavailableMetersFromDisabledMetersInEmptyState() {
        let unavailableMeter = UsageMeterViewData(
            id: .primary,
            kind: .rateLimit,
            title: "Main window",
            valueText: "Unavailable",
            resetText: nil,
            remainingPercent: nil,
            level: .neutral,
            resetDate: nil,
            isAvailable: false
        )
        let snapshot = UsageSnapshot(
            meters: [unavailableMeter],
            lastUpdated: Date(),
            warningMessage: nil
        )
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(snapshot)])
        )

        #expect(viewModel.visibleMeters(in: snapshot).isEmpty)
        #expect(
            viewModel.meterEmptyStateMessage(in: snapshot)
                == "No usage meters are currently available."
        )

        viewModel.setMeterVisible(false, meterID: .primary)

        #expect(
            viewModel.meterEmptyStateMessage(in: snapshot)
                == "No meters are enabled. You can enable meters in Settings."
        )
    }

    @MainActor
    @Test
    func menuOpenedRefreshesWhenPollOnMenuOpenIsEnabled() async throws {
        let tracker = RefreshTracker()
        let service = BlockingUsageFetcher(tracker: tracker, snapshot: makeSnapshot())
        let viewModel = makeViewModel(service: service)

        viewModel.menuOpened()
        await tracker.waitUntilCalled()

        #expect(await tracker.callCount == 1)
        await tracker.resume()
        try await waitUntil { viewModel.loadState == .loaded }
    }

    @MainActor
    @Test
    func menuOpenedDoesNotRefreshWhenPollOnMenuOpenIsDisabled() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        store.pollOnMenuOpen = false
        let tracker = RefreshTracker()
        let service = BlockingUsageFetcher(tracker: tracker, snapshot: makeSnapshot())
        let viewModel = makeViewModel(service: service, preferencesStore: store)

        viewModel.menuOpened()
        try await Task.sleep(for: .milliseconds(50))

        #expect(await tracker.callCount == 0)
        #expect(viewModel.pollOnMenuOpen == false)
    }

    @MainActor
    @Test
    func persistsPollOnMenuOpenPreference() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.success(makeSnapshot())]), preferencesStore: store)

        viewModel.setPollOnMenuOpen(false)

        #expect(viewModel.pollOnMenuOpen == false)
        #expect(store.pollOnMenuOpen == false)
    }

    @MainActor
    @Test
    func readsLaunchAtLoginStatusOnInit() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let loginItemService = MockLoginItemService(isEnabled: true)

        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store,
            loginItemService: loginItemService
        )

        #expect(viewModel.launchAtLoginEnabled)
        #expect(store.launchAtLoginEnabled)
    }

    @MainActor
    @Test
    func launchAtLoginTogglePersistsOnSuccess() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let loginItemService = MockLoginItemService(isEnabled: false)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store,
            loginItemService: loginItemService
        )

        viewModel.setLaunchAtLoginEnabled(true)

        #expect(viewModel.launchAtLoginEnabled)
        #expect(store.launchAtLoginEnabled)
        #expect(loginItemService.requestedValues == [true])
        #expect(viewModel.settingsErrorMessage == nil)
    }

    @MainActor
    @Test
    func launchAtLoginToggleRevertsOnFailure() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let loginItemService = MockLoginItemService(isEnabled: false, shouldFail: true)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store,
            loginItemService: loginItemService
        )

        viewModel.setLaunchAtLoginEnabled(true)

        #expect(viewModel.launchAtLoginEnabled == false)
        #expect(store.launchAtLoginEnabled == false)
        #expect(loginItemService.requestedValues == [true])
        #expect(viewModel.settingsErrorMessage == "Could not update launch at login.")
    }

    @MainActor
    @Test
    func persistsResetNotificationSettingAndRequestsPermission() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)
        let notificationService = MockNotificationService()
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store,
            notificationService: notificationService
        )

        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        try await waitUntil { notificationService.authorizationRequestCount == 1 }

        #expect(viewModel.preferences(for: .primary).resetNotificationsEnabled)
        #expect(store.meterPreferences[.primary]?.resetNotificationsEnabled == true)
    }
}
