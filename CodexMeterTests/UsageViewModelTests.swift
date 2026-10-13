import Foundation
import Testing
import UserNotifications
@testable import CodexMeter

@MainActor
struct UsageViewModelTests {
    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional])
    func authorizedPreferenceChangesAreSynchronous(status: UNAuthorizationStatus) async {
        let notifications = MockNotificationService(status: status)
        let viewModel = makeViewModel(service: MockUsageFetcher(results: []), notificationService: notifications)
        await viewModel.refreshNotificationAuthorization()

        viewModel.selectNotificationThreshold(.twenty, meterID: .primary)
        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        viewModel.selectCreditsNotificationThreshold(.ten)
        viewModel.setNotificationEnabled(true, meterID: .credits, preference: \.creditsAddedNotificationsEnabled)
        viewModel.setNotificationEnabled(true, meterID: .usageLimitResets, preference: \.resetsUsedNotificationsEnabled)
        viewModel.setNotificationEnabled(true, meterID: .usageLimitResets, preference: \.resetsAddedNotificationsEnabled)

        #expect(viewModel.preferences(for: .primary) == MeterPreferences(notificationThreshold: .twenty, resetNotificationsEnabled: true))
        #expect(viewModel.preferences(for: .credits) == MeterPreferences(creditsNotificationThreshold: .ten, creditsAddedNotificationsEnabled: true))
        #expect(viewModel.preferences(for: .usageLimitResets) == MeterPreferences(resetsUsedNotificationsEnabled: true, resetsAddedNotificationsEnabled: true))
        #expect(viewModel.canEditNotificationPreferences)
        #expect(!viewModel.isRequestingNotificationAuthorization)
        #expect(notifications.authorizationRequestCount == 0)
    }

    @Test
    func deniedPermissionMasksEvaluationAndAmountPreferenceUpdates() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PreferencesStore(userDefaults: defaults)
        let saved: [UsageMeterID: MeterPreferences] = [
            .primary: MeterPreferences(notificationThreshold: .twenty, resetNotificationsEnabled: true),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten, creditsAddedNotificationsEnabled: true)
        ]
        store.meterPreferences = saved
        let notifications = MockNotificationService(status: .denied)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store, notificationService: notifications
        )
        await viewModel.refreshNotificationAuthorization()
        viewModel.refreshNow()
        try await waitUntil { notifications.evaluationCount == 1 }
        #expect(notifications.lastEvaluationSettings[.primary] == MeterPreferences())
        #expect(notifications.lastEvaluationSettings[.credits] == MeterPreferences())

        viewModel.setMeterVisible(true, meterID: .credits)
        try await waitUntil { notifications.lastAmountPreferences[.credits] != nil }
        #expect(notifications.lastAmountPreferences[.credits] == MeterPreferences())
        #expect(store.meterPreferences == saved)
    }

    @Test
    func permissionLossWithoutAPollRearmsRateLimitAndCreditAlerts() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PreferencesStore(userDefaults: defaults)
        store.meterPreferences = [
            .primary: MeterPreferences(notificationThreshold: .twenty),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten)
        ]
        let permission = MockNotificationService()
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: { true },
            authorizationStatusProvider: { await permission.authorizationStatus() },
            requestDeliverer: { request in await tracker.record(request: request) }
        )
        let notifications = MockNotificationService(underlying: service)
        let lowCredits = UsageFormatting.snapshot(from: UsageResponse(
            planType: nil, rateLimit: nil, additionalRateLimits: nil,
            credits: CreditsInfo(unlimited: false, balance: .int(9), hasCredits: true)
        ))
        let snapshot = UsageSnapshot(
            meters: makeSnapshot(fiveHourRemaining: 10).meters.filter { $0.kind == .rateLimit }
                + lowCredits.meters.filter { $0.kind == .credits },
            lastUpdated: lowCredits.lastUpdated, warningMessage: nil
        )
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(snapshot), .success(snapshot)]),
            preferencesStore: store, notificationService: notifications
        )
        await viewModel.refreshNotificationAuthorization()
        viewModel.refreshNow()
        try await waitUntil { notifications.evaluationCount == 1 }
        #expect(await tracker.identifiers.count == 2)
        permission.setAuthorizationStatus(.denied)
        await viewModel.refreshNotificationAuthorization()
        try await waitUntil { notifications.evaluationCount == 2 }
        #expect(await tracker.identifiers.count == 2)
        permission.setAuthorizationStatus(.authorized)
        await viewModel.refreshNotificationAuthorization()
        try await waitUntil { notifications.evaluationCount == 3 }
        #expect(await tracker.identifiers.count == 4)
        viewModel.refreshNow()
        try await waitUntil { notifications.evaluationCount == 4 }
        #expect(await tracker.identifiers.count == 4)
    }

    @Test
    func notificationPermissionRefreshNeverPrompts() async {
        let notifications = MockNotificationService(status: .notDetermined)
        let viewModel = makeViewModel(service: MockUsageFetcher(results: []), notificationService: notifications)

        #expect(!viewModel.canEditNotificationPreferences)
        await viewModel.refreshNotificationAuthorization()

        #expect(viewModel.notificationAuthorizationStatus == .notDetermined)
        #expect(viewModel.canEditNotificationPreferences)
        #expect(notifications.authorizationRequestCount == 0)
    }

    @Test
    func notificationChoicesStayOffUntilPermissionIsGranted() async throws {
        let tracker = RefreshTracker()
        let notifications = MockNotificationService(status: .notDetermined, authorizationRequester: {
            await tracker.recordCallAndWaitUntilResumed()
            return true
        })
        let viewModel = makeViewModel(service: MockUsageFetcher(results: []), notificationService: notifications)
        await viewModel.refreshNotificationAuthorization()
        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        await tracker.waitUntilCalled()

        #expect(viewModel.isRequestingNotificationAuthorization)
        #expect(!viewModel.canEditNotificationPreferences)
        #expect(!viewModel.preferences(for: .primary).resetNotificationsEnabled)
        #expect(!viewModel.notificationPreferences(for: .primary).resetNotificationsEnabled)

        await tracker.resume()
        try await waitUntil { viewModel.preferences(for: .primary).resetNotificationsEnabled }
        #expect(viewModel.notificationPreferences(for: .primary).resetNotificationsEnabled)
        #expect(viewModel.canEditNotificationPreferences)
    }

    @Test
    func deniedPermissionDoesNotSaveRequestedNotificationChoices() async throws {
        let notifications = MockNotificationService(status: .notDetermined, authorizationRequester: { false })
        let viewModel = makeViewModel(service: MockUsageFetcher(results: []), notificationService: notifications)

        viewModel.selectNotificationThreshold(.twenty, meterID: .primary)
        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        viewModel.selectCreditsNotificationThreshold(.ten)
        viewModel.setNotificationEnabled(true, meterID: .credits, preference: \.creditsAddedNotificationsEnabled)
        viewModel.setNotificationEnabled(true, meterID: .usageLimitResets, preference: \.resetsUsedNotificationsEnabled)
        viewModel.setNotificationEnabled(true, meterID: .usageLimitResets, preference: \.resetsAddedNotificationsEnabled)
        try await waitUntil { viewModel.notificationsBlocked && !viewModel.isRequestingNotificationAuthorization }

        #expect(!viewModel.canEditNotificationPreferences)
        #expect(viewModel.preferences(for: .primary) == MeterPreferences())
        #expect(viewModel.preferences(for: .credits) == MeterPreferences())
        #expect(viewModel.preferences(for: .usageLimitResets) == MeterPreferences())
        #expect(notifications.authorizationRequestCount == 1)
    }

    @Test
    func externalPermissionChangesMaskAndRestoreAllSavedNotificationChoices() async {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PreferencesStore(userDefaults: defaults)
        let saved: [UsageMeterID: MeterPreferences] = [
            .primary: MeterPreferences(notificationThreshold: .twenty, resetNotificationsEnabled: true),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten, creditsAddedNotificationsEnabled: true),
            .usageLimitResets: MeterPreferences(resetsUsedNotificationsEnabled: true, resetsAddedNotificationsEnabled: true)
        ]
        store.meterPreferences = saved
        let notifications = MockNotificationService()
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: []), preferencesStore: store, notificationService: notifications
        )

        await viewModel.refreshNotificationAuthorization()
        for (meterID, preferences) in saved {
            #expect(viewModel.notificationPreferences(for: meterID) == preferences)
        }

        notifications.setAuthorizationStatus(.denied)
        await viewModel.refreshNotificationAuthorization()
        #expect(viewModel.notificationsBlocked)
        #expect(!viewModel.canEditNotificationPreferences)
        for meterID in saved.keys {
            #expect(viewModel.notificationPreferences(for: meterID) == MeterPreferences())
        }
        #expect(store.meterPreferences == saved)

        notifications.setAuthorizationStatus(.authorized)
        await viewModel.refreshNotificationAuthorization()
        #expect(viewModel.canEditNotificationPreferences)
        for (meterID, preferences) in saved {
            #expect(viewModel.notificationPreferences(for: meterID) == preferences)
        }
        #expect(store.meterPreferences == saved)
        #expect(notifications.authorizationRequestCount == 0)
    }

    @Test
    func failedPermissionRequestShowsAnErrorAndCanBeRetried() async throws {
        let notifications = MockNotificationService(status: .notDetermined, authorizationRequester: {
            throw NSError(domain: "NotificationTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service unavailable."])
        })
        let viewModel = makeViewModel(service: MockUsageFetcher(results: []), notificationService: notifications)
        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        try await waitUntil { viewModel.notificationPermissionErrorMessage != nil && !viewModel.isRequestingNotificationAuthorization }

        #expect(viewModel.notificationPermissionErrorMessage == "Could not request notification permission. Service unavailable.")
        #expect(!viewModel.preferences(for: .primary).resetNotificationsEnabled)
        #expect(viewModel.canEditNotificationPreferences)
        notifications.setAuthorizationStatus(.authorized)
        await viewModel.refreshNotificationAuthorization()
        #expect(viewModel.notificationPermissionErrorMessage == nil)
    }

    @Test
    func disablingAPreferenceWhilePermissionIsPendingCancelsThatChoice() async throws {
        let tracker = RefreshTracker()
        let notifications = MockNotificationService(status: .notDetermined, authorizationRequester: {
            await tracker.recordCallAndWaitUntilResumed()
            return true
        })
        let viewModel = makeViewModel(service: MockUsageFetcher(results: []), notificationService: notifications)
        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        await tracker.waitUntilCalled()
        viewModel.setResetNotificationsEnabled(false, meterID: .primary)
        await tracker.resume()
        try await waitUntil { !viewModel.isRequestingNotificationAuthorization }

        #expect(!viewModel.preferences(for: .primary).resetNotificationsEnabled)
    }

    @Test
    func denialReportedAsAnErrorUsesOnlyTheBlockedNotice() async throws {
        let notifications = MockNotificationService(status: .notDetermined)
        let service = NotificationService(
            authorizationRequester: {
                notifications.setAuthorizationStatus(.denied)
                throw NSError(domain: "NotificationTest", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Notifications are not allowed for this application"
                ])
            },
            authorizationStatusProvider: { await notifications.authorizationStatus() },
            requestDeliverer: { _ in }
        )
        let viewModel = makeViewModel(service: MockUsageFetcher(results: []), notificationService: service)
        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        try await waitUntil { viewModel.notificationsBlocked && !viewModel.isRequestingNotificationAuthorization }

        #expect(viewModel.notificationPermissionErrorMessage == nil)
        #expect(!viewModel.preferences(for: .primary).resetNotificationsEnabled)
        #expect(!viewModel.canEditNotificationPreferences)
    }

    @Test(arguments: [
        (UsageMeterID.credits, true),
        (.usageLimitResets, true),
        (.usageLimitResets, false)
    ])
    func enablingBalanceNotificationsReportsTheFirstChange(meterID: UsageMeterID, increases: Bool) async throws {
        let tracker = NotificationTracker()
        let notifications = MockNotificationService(underlying: makeNotificationService(tracker: tracker))
        let initial = UsageFormatting.snapshot(from: UsageResponse(
            planType: nil, rateLimit: nil, additionalRateLimits: nil,
            credits: CreditsInfo(unlimited: false, balance: .int(10), hasCredits: true),
            rateLimitResetCredits: RateLimitResetCreditsInfo(availableCount: 3)
        ))
        let updated = UsageFormatting.snapshot(from: UsageResponse(
            planType: nil, rateLimit: nil, additionalRateLimits: nil,
            credits: CreditsInfo(unlimited: false, balance: .int(20), hasCredits: true),
            rateLimitResetCredits: RateLimitResetCreditsInfo(availableCount: increases ? 4 : 2)
        ))
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(updated)]),
            notificationService: notifications
        )
        await viewModel.refreshNotificationAuthorization()
        viewModel.applyPreviewSnapshot(initial)

        let preference: WritableKeyPath<MeterPreferences, Bool> = meterID == .credits
            ? \.creditsAddedNotificationsEnabled
            : increases ? \.resetsAddedNotificationsEnabled : \.resetsUsedNotificationsEnabled
        viewModel.setNotificationEnabled(true, meterID: meterID, preference: preference)
        #expect(viewModel.preferences(for: meterID)[keyPath: preference])
        viewModel.refreshNow()
        try await waitUntil { notifications.evaluationCount == 1 }

        let expectedBody = meterID == .credits
            ? "20 credits remaining."
            : increases
                ? "4 usage limit resets remaining."
                : "2 usage limit resets remaining. A reset was used or expired."
        #expect(await tracker.bodies == [expectedBody])
    }

    @Test
    func persistsBalanceNotificationOptionsAndRequestsPermission() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PreferencesStore(userDefaults: defaults)
        let notifications = MockNotificationService(status: .notDetermined)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: []),
            preferencesStore: store,
            notificationService: notifications
        )
        viewModel.selectCreditsNotificationThreshold(.fifty)
        viewModel.setNotificationEnabled(true, meterID: .credits, preference: \.creditsAddedNotificationsEnabled)
        viewModel.setNotificationEnabled(true, meterID: .usageLimitResets, preference: \.resetsUsedNotificationsEnabled)
        viewModel.setNotificationEnabled(true, meterID: .usageLimitResets, preference: \.resetsAddedNotificationsEnabled)
        try await waitUntil {
            viewModel.preferences(for: .credits).creditsAddedNotificationsEnabled
                && viewModel.preferences(for: .usageLimitResets).resetsUsedNotificationsEnabled
                && viewModel.preferences(for: .usageLimitResets).resetsAddedNotificationsEnabled
                && viewModel.preferences(for: .credits).creditsNotificationThreshold == .fifty
        }
        #expect(notifications.authorizationRequestCount == 1)
        #expect(store.meterPreferences[.credits] == MeterPreferences(creditsNotificationThreshold: .fifty, creditsAddedNotificationsEnabled: true))
        #expect(store.meterPreferences[.usageLimitResets] == MeterPreferences(resetsUsedNotificationsEnabled: true, resetsAddedNotificationsEnabled: true))

        viewModel.selectCreditsNotificationThreshold(nil)
        viewModel.setNotificationEnabled(false, meterID: .credits, preference: \.creditsAddedNotificationsEnabled)
        #expect(store.meterPreferences[.credits] == MeterPreferences())
        #expect(notifications.authorizationRequestCount == 1)
    }

    @Test
    func usageLimitResetsVisibilityPersistsIndependentlyOfCredits() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }
        let store = PreferencesStore(userDefaults: defaults)
        let response = UsageResponse(
            planType: nil,
            rateLimit: nil,
            additionalRateLimits: nil,
            credits: CreditsInfo(unlimited: false, balance: .int(12), hasCredits: true),
            rateLimitResetCredits: RateLimitResetCreditsInfo(availableCount: 3)
        )
        let snapshot = UsageFormatting.snapshot(from: response)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(snapshot)]),
            preferencesStore: store
        )
        viewModel.refreshNow()
        try await waitUntil { viewModel.loadState == .loaded }

        #expect(viewModel.visibleMeters(in: snapshot).map(\.id) == [.credits, .usageLimitResets])
        viewModel.setMeterVisible(false, meterID: .usageLimitResets)
        #expect(viewModel.visibleMeters(in: snapshot).map(\.id) == [.credits])

        let restoredViewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(snapshot)]),
            preferencesStore: PreferencesStore(userDefaults: defaults)
        )
        #expect(restoredViewModel.visibleMeters(in: snapshot).map(\.id) == [.credits])
        restoredViewModel.setMeterVisible(true, meterID: .usageLimitResets)
        #expect(restoredViewModel.visibleMeters(in: snapshot).map(\.id) == [.credits, .usageLimitResets])
    }

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
        // Snapshot publication precedes completion of notification evaluation.
        // Retry while the first refresh is still coalescing new requests.
        try await waitUntil {
            if viewModel.snapshot?.warningMessage == "Offline" { return true }
            viewModel.refreshNow()
            return false
        }

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
        try await waitUntil {
            if viewModel.snapshot?.warningMessage == "Auth token unavailable. Open Codex to refresh it." { return true }
            viewModel.refreshNow()
            return false
        }

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
        let notificationService = MockNotificationService(status: .notDetermined)
        let viewModel = makeViewModel(
            service: MockUsageFetcher(results: [.success(makeSnapshot())]),
            preferencesStore: store,
            notificationService: notificationService
        )

        viewModel.setResetNotificationsEnabled(true, meterID: .primary)
        try await waitUntil { viewModel.preferences(for: .primary).resetNotificationsEnabled }
        #expect(notificationService.authorizationRequestCount == 1)

        #expect(viewModel.preferences(for: .primary).resetNotificationsEnabled)
        #expect(store.meterPreferences[.primary]?.resetNotificationsEnabled == true)
    }
}
