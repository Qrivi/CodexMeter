import Foundation
import Testing
import UserNotifications
@testable import CodexMeter

struct CodexMeterTests {
    @Test
    func formattingMapsUsedPercentToRemainingPercent() {
        #expect(UsageFormatting.remainingPercent(from: 36) == 64)
        #expect(UsageFormatting.remainingPercent(from: 100) == 0)
    }

    @Test
    func formattingBuildsResetTextFromResetAt() {
        let now = Date(timeIntervalSince1970: 1_778_054_820) // 2026-05-05 10:07 UTC
        let resetDate = Date(timeIntervalSince1970: 1_778_070_900) // 2026-05-05 14:35 UTC

        let text = UsageFormatting.resetText(
            resetDate: resetDate,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "Resets 2:35 PM (4h 28m)")
    }

    @Test
    func formattingBuildsResetTextWithDateWhenResetIsAnotherDay() {
        let now = Date(timeIntervalSince1970: 1_778_054_820) // 2026-05-05 10:07 UTC
        let resetDate = Date(timeIntervalSince1970: 1_778_141_800) // 2026-05-06 10:30 UTC

        let text = UsageFormatting.resetText(
            resetDate: resetDate,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "Resets May 6, 2026 10:30 AM (1d 0h)")
    }

    @Test
    func formattingBuildsLastUpdatedTextWithTimeWhenUpdatedToday() {
        let now = Date(timeIntervalSince1970: 1_778_054_820) // 2026-05-05 10:07 UTC
        let lastUpdated = Date(timeIntervalSince1970: 1_778_054_340) // 2026-05-05 09:59 UTC

        let text = UsageFormatting.lastUpdatedText(
            from: lastUpdated,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "9:59 AM")
    }

    @Test
    func formattingBuildsLastUpdatedTextWithDateWhenUpdatedAnotherDay() {
        let now = Date(timeIntervalSince1970: 1_778_141_800) // 2026-05-06 10:30 UTC
        let lastUpdated = Date(timeIntervalSince1970: 1_778_054_820) // 2026-05-05 10:07 UTC

        let text = UsageFormatting.lastUpdatedText(
            from: lastUpdated,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "May 5, 2026, 10:07 AM")
    }

    @Test
    func formattingFallsBackToResetAfterSeconds() {
        let now = Date(timeIntervalSince1970: 1_778_054_820)
        let window = UsageWindow(
            usedPercent: 36,
            limitWindowSeconds: 18_000,
            resetAfterSeconds: 7_200,
            resetAt: nil
        )

        let resetDate = UsageFormatting.resetDate(for: window, now: now)

        #expect(resetDate == now.addingTimeInterval(7_200))
    }

    @Test
    func formattingRendersCreditsAsUnlimitedOrRawBalance() {
        let unlimitedCredits = CreditsInfo(unlimited: true, balance: .int(0), hasCredits: true)
        let finiteCredits = CreditsInfo(unlimited: false, balance: .string("42.5"), hasCredits: true)

        #expect(UsageFormatting.creditsText(from: unlimitedCredits) == "Unlimited")
        #expect(UsageFormatting.creditsText(from: finiteCredits) == "42.5")
    }

    @Test
    func preferencesProvideExpectedDefaults() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)

        #expect(store.pollingInterval == .minutes5)
        #expect(store.menuBarDisplayMode == .both)
        #expect(store.notificationThreshold == nil)
    }

    @Test
    func preferencesPersistAndReloadValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        var store = PreferencesStore(userDefaults: defaults)
        store.pollingInterval = .minutes10
        store.menuBarDisplayMode = .both
        store.notificationThreshold = .ten

        store = PreferencesStore(userDefaults: defaults)

        #expect(store.pollingInterval == .minutes10)
        #expect(store.menuBarDisplayMode == .both)
        #expect(store.notificationThreshold == .ten)
    }

    @Test
    func usageServiceDecodesSuccessfulResponseIntoSnapshot() async throws {
        let payload = """
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 36,
              "limit_window_seconds": 18000,
              "reset_at": 1778070900
            },
            "secondary_window": {
              "used_percent": 27,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 86400
            }
          },
          "credits": {
            "unlimited": false,
            "balance": "12",
            "has_credits": true
          }
        }
        """

        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: "acct"))),
            now: { Date(timeIntervalSince1970: 1_778_054_820) },
            requestPerformer: { request in
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
                #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct")
                return (
                    Data(payload.utf8),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let snapshot = try await service.fetchUsageSnapshot()

        #expect(snapshot.fiveHourSection.remainingPercent == 64)
        #expect(snapshot.weeklySection.remainingPercent == 73)
        #expect(snapshot.creditsText == "12")
    }

    @Test
    func usageServiceReturnsAuthErrorWhenTokenIsMissing() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .failure(AuthTokenProviderError.missingToken)),
            requestPerformer: { _ in
                Issue.record("Request performer should not be called when auth fails.")
                throw URLError(.badURL)
            }
        )

        await #expect(throws: UsageServiceError.auth(.missingToken)) {
            try await service.fetchUsageSnapshot()
        }
    }

    @Test
    func usageServiceReturnsUnauthorizedFor401() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: nil))),
            requestPerformer: { _ in
                (
                    Data(),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 401, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: UsageServiceError.unauthorized) {
            try await service.fetchUsageSnapshot()
        }
    }

    @Test
    func usageServiceReturnsNetworkErrorForTransportFailure() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: nil))),
            requestPerformer: { _ in
                throw URLError(.notConnectedToInternet)
            }
        )

        await #expect(throws: UsageServiceError.network(URLError(.notConnectedToInternet).localizedDescription)) {
            try await service.fetchUsageSnapshot()
        }
    }

    @Test
    func usageServiceReturnsDecodingErrorForInvalidJSON() async {
        let service = UsageService(
            tokenProvider: MockTokenProvider(result: .success(AuthSession(accessToken: "token", accountID: nil))),
            requestPerformer: { _ in
                (
                    Data("not-json".utf8),
                    HTTPURLResponse(url: UsageService.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: UsageServiceError.decoding) {
            try await service.fetchUsageSnapshot()
        }
    }

    @Test
    func enablingNotificationsRequestsPermission() async {
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: {
                await tracker.markAuthorizationRequested()
                return true
            },
            authorizationStatusProvider: {
                .notDetermined
            },
            requestDeliverer: { _ in }
        )

        let granted = await service.requestAuthorizationIfNeeded()

        #expect(granted)
        #expect(await tracker.authorizationRequestCount == 1)
    }

    @Test
    func notificationsFireWhenUsageCrossesBelowThreshold() async {
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: { true },
            authorizationStatusProvider: { .authorized },
            requestDeliverer: { request in
                await tracker.record(identifier: request.identifier)
            }
        )

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 25, weeklyRemaining: 50), threshold: .twenty)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 20, weeklyRemaining: 50), threshold: .twenty)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-20"])
    }

    @Test
    func notificationsDoNotRepeatWhileStillBelowThreshold() async {
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: { true },
            authorizationStatusProvider: { .authorized },
            requestDeliverer: { request in
                await tracker.record(identifier: request.identifier)
            }
        )

        let snapshot = makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50)
        await service.evaluateNotifications(for: snapshot, threshold: .twenty)
        await service.evaluateNotifications(for: snapshot, threshold: .twenty)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-20"])
    }

    @Test
    func notificationsBecomeEligibleAgainAfterReset() async {
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: { true },
            authorizationStatusProvider: { .authorized },
            requestDeliverer: { request in
                await tracker.record(identifier: request.identifier)
            }
        )

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50, fiveHourReset: Date(timeIntervalSince1970: 100)), threshold: .twenty)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50, fiveHourReset: Date(timeIntervalSince1970: 200)), threshold: .twenty)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-20", "codexmeter-fiveHour-20"])
    }

    @Test
    func notificationsTrackFiveHourAndWeeklyWindowsIndependently() async {
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: { true },
            authorizationStatusProvider: { .authorized },
            requestDeliverer: { request in
                await tracker.record(identifier: request.identifier)
            }
        )

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 10, weeklyRemaining: 10), threshold: .twenty)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-20", "codexmeter-weekly-20"])
    }

    @Test
    func notificationsBecomeEligibleAgainWhenThresholdChanges() async {
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: { true },
            authorizationStatusProvider: { .authorized },
            requestDeliverer: { request in
                await tracker.record(identifier: request.identifier)
            }
        )

        let snapshot = makeSnapshot(fiveHourRemaining: 9, weeklyRemaining: 50)
        await service.updateThreshold(.ten)
        await service.evaluateNotifications(for: snapshot, threshold: .ten)
        await service.updateThreshold(.twenty)
        await service.evaluateNotifications(for: snapshot, threshold: .twenty)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-10", "codexmeter-fiveHour-20"])
    }

    @MainActor
    @Test
    func viewModelLaunchRefreshPopulatesSnapshot() async throws {
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.success(makeSnapshot())]))

        viewModel.start()
        try await waitUntil { viewModel.loadState == .loaded }

        #expect(viewModel.snapshot?.fiveHourSection.remainingPercent == 64)
        #expect(viewModel.loadState == .loaded)
    }

    @MainActor
    @Test
    func viewModelDoesNotOverlapRefreshRequests() async throws {
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
    func viewModelPreservesLastGoodDataAfterRefreshFailure() async throws {
        let initialSnapshot = makeSnapshot()
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [
            .success(initialSnapshot),
            .failure(UsageServiceError.network("Offline"))
        ]))

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }
        viewModel.refreshNow()
        try await waitUntil { viewModel.snapshot?.warningMessage == "Update failed" }

        #expect(viewModel.snapshot?.fiveHourSection.remainingPercent == initialSnapshot.fiveHourSection.remainingPercent)
        #expect(viewModel.snapshot?.warningMessage == "Update failed")
    }

    @MainActor
    @Test
    func viewModelShowsAuthGuidanceForAuthenticationFailure() async throws {
        let viewModel = makeViewModel(service: MockUsageFetcher(results: [.failure(UsageServiceError.unauthorized)]))

        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .authFailure(message: "Auth token unavailable. Open Codex to refresh it.") }

        #expect(viewModel.currentFailureMessage == "Auth token unavailable. Open Codex to refresh it.")
        #expect(viewModel.loadState == .authFailure(message: "Auth token unavailable. Open Codex to refresh it."))
    }

    @MainActor
    @Test
    func viewModelReschedulesPollingWhenIntervalChanges() {
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
    func viewModelUpdatesMenuBarLabelWhenDisplayModeChanges() async throws {
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

    @Test
    func launcherOpensDashboardURL() async {
        let tracker = LauncherRecorder()
        let launcher = AppLauncher(
            bundleIdentifierResolver: { _ in nil },
            fallbackURLResolver: { nil },
            urlOpener: { url in
                tracker.recordURL(url)
                return true
            },
            applicationOpener: { _ in true }
        )

        let success = await launcher.openUsageDashboard()

        #expect(success)
        #expect(tracker.urls == [AppLauncher.usageDashboardURL])
    }

    @Test
    func launcherPrefersBundleIdentifierWhenOpeningCodex() async {
        let tracker = LauncherRecorder()
        let bundleURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let launcher = AppLauncher(
            bundleIdentifierResolver: { identifier in
                tracker.recordStep(identifier)
                return bundleURL
            },
            fallbackURLResolver: {
                tracker.recordStep("fallback")
                return URL(fileURLWithPath: "/Fallback/Codex.app")
            },
            urlOpener: { _ in true },
            applicationOpener: { url in
                tracker.recordURL(url)
                return true
            }
        )

        let success = await launcher.openCodex()

        #expect(success)
        #expect(tracker.steps == ["com.openai.codex"])
        #expect(tracker.urls == [bundleURL])
    }
}

private struct MockTokenProvider: TokenProviding {
    let result: Result<AuthSession, Error>

    func currentSession() async throws -> AuthSession {
        try result.get()
    }
}

private actor MockUsageFetcher: UsageFetching {
    private var results: [Result<UsageSnapshot, Error>]

    init(results: [Result<UsageSnapshot, Error>]) {
        self.results = results
    }

    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        let result = results.removeFirst()
        return try result.get()
    }
}

private actor BlockingUsageFetcher: UsageFetching {
    private let tracker: RefreshTracker
    private let snapshot: UsageSnapshot

    init(tracker: RefreshTracker, snapshot: UsageSnapshot) {
        self.tracker = tracker
        self.snapshot = snapshot
    }

    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        await tracker.recordCallAndWaitUntilResumed()
        return snapshot
    }
}

private actor RefreshTracker {
    private var callCountValue = 0
    private var callContinuation: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    var callCount: Int {
        get { callCountValue }
    }

    func recordCallAndWaitUntilResumed() async {
        callCountValue += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            callContinuation?.resume()
            callContinuation = nil
        }
    }

    func waitUntilCalled() async {
        if callCountValue > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            callContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor NotificationTracker {
    private(set) var identifiers: [String] = []
    private(set) var authorizationRequestCount = 0

    func record(identifier: String) {
        identifiers.append(identifier)
    }

    func markAuthorizationRequested() {
        authorizationRequestCount += 1
    }
}

private final class LauncherRecorder: @unchecked Sendable {
    private(set) var urls: [URL] = []
    private(set) var steps: [String] = []

    func recordURL(_ url: URL) {
        urls.append(url)
    }

    func recordStep(_ step: String) {
        steps.append(step)
    }
}

private struct MockNotificationService: NotificationScheduling {
    func requestAuthorizationIfNeeded() async -> Bool { true }
    func updateThreshold(_ threshold: NotificationThreshold?) async {}
    func evaluateNotifications(for snapshot: UsageSnapshot, threshold: NotificationThreshold?) async {}
}

private enum WaitTimeout: Error {
    case timedOut
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while condition() == false {
        if clock.now >= deadline {
            throw WaitTimeout.timedOut
        }

        try await Task.sleep(for: .milliseconds(10))
    }
}

private struct MockAppLauncher: AppLaunching {
    func openUsageDashboard() async -> Bool { true }
    func openCodex() async -> Bool { true }
}

@MainActor
private func makeViewModel(
    service: UsageFetching,
    preferencesStore: PreferencesStore? = nil
) -> UsageViewModel {
    let store = preferencesStore ?? PreferencesStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    return UsageViewModel(
        usageService: service,
        preferencesStore: store,
        appLauncher: MockAppLauncher(),
        notificationService: MockNotificationService(),
        wakeNotificationCenter: NotificationCenter()
    )
}

private func makeSnapshot(
    fiveHourRemaining: Int = 64,
    weeklyRemaining: Int = 73,
    fiveHourReset: Date = Date(timeIntervalSince1970: 1_778_070_900),
    weeklyReset: Date = Date(timeIntervalSince1970: 1_778_141_800)
) -> UsageSnapshot {
    UsageSnapshot(
        fiveHourSection: UsageSectionViewData(
            title: "5 hour usage limit",
            remainingText: "\(fiveHourRemaining)% remaining",
            resetText: "Resets 2:35 PM (4h 28m)",
            remainingPercent: fiveHourRemaining,
            level: UsageFormatting.level(for: fiveHourRemaining),
            resetDate: fiveHourReset,
            windowKind: .fiveHour
        ),
        weeklySection: UsageSectionViewData(
            title: "Weekly usage limit",
            remainingText: "\(weeklyRemaining)% remaining",
            resetText: "Resets May 6, 2026 10:30 AM (1d 0h)",
            remainingPercent: weeklyRemaining,
            level: UsageFormatting.level(for: weeklyRemaining),
            resetDate: weeklyReset,
            windowKind: .weekly
        ),
        creditsText: "12",
        lastUpdated: Date(timeIntervalSince1970: 1_778_054_820),
        warningMessage: nil,
        authGuidanceMessage: nil
    )
}
