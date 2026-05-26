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

        #expect(viewModel.snapshot?.fiveHourSection.remainingPercent == 64)
        #expect(viewModel.loadState == .loaded)
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

        #expect(viewModel.snapshot?.fiveHourSection.remainingPercent == initialSnapshot.fiveHourSection.remainingPercent)
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

        #expect(viewModel.snapshot?.fiveHourSection.remainingPercent == initialSnapshot.fiveHourSection.remainingPercent)
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

        viewModel.setResetNotificationsEnabled(true)
        try await waitUntil { notificationService.authorizationRequestCount == 1 }

        #expect(viewModel.resetNotificationsEnabled)
        #expect(store.resetNotificationsEnabled)
    }
}
