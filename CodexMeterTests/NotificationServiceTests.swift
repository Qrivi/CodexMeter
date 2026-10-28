import Foundation
import Testing
import UserNotifications
@testable import CodexMeter

@MainActor
struct NotificationServiceTests {
    @Test(arguments: [UNAuthorizationStatus.authorized, .provisional, .denied])
    func existingPermissionDoesNotPromptAgain(status: UNAuthorizationStatus) async throws {
        let tracker = NotificationTracker()
        let service = NotificationService(
            authorizationRequester: {
                await tracker.markAuthorizationRequested()
                return true
            },
            authorizationStatusProvider: { status },
            requestDeliverer: { _ in }
        )

        #expect(await service.authorizationStatus() == status)
        #expect(try await service.requestAuthorizationIfNeeded() == (status != .denied))
        #expect(await tracker.authorizationRequestCount == 0)
    }

    @Test
    func permissionRequestErrorsArePropagated() async {
        let service = NotificationService(
            authorizationRequester: { throw URLError(.notConnectedToInternet) },
            authorizationStatusProvider: { .notDetermined },
            requestDeliverer: { _ in }
        )
        await #expect(throws: URLError.self) {
            try await service.requestAuthorizationIfNeeded()
        }
    }

    @Test
    func balancePreferenceUpdatesDoNotSendNotificationsOrRepeatLowCreditAlerts() async throws {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let snapshot = balanceSnapshot(credits: 9)
        var preferences = MeterPreferences(creditsNotificationThreshold: .ten)
        await service.evaluateNotifications(for: snapshot, settings: [.credits: preferences])

        preferences.creditsAddedNotificationsEnabled = true
        await service.updateAmountNotificationPreferences(for: try #require(snapshot.creditsMeter), preferences: preferences)
        await service.evaluateNotifications(for: snapshot, settings: [.credits: preferences])
        #expect(await tracker.bodies == ["9 credits remaining."])

        await service.evaluateNotifications(for: balanceSnapshot(credits: 20), settings: [.credits: preferences])
        #expect(await tracker.bodies == ["9 credits remaining.", "20 credits remaining."])
    }

    @Test
    func disablingAndReenablingBalanceNotificationsReseedsWithoutAPoll() async throws {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let enabled = MeterPreferences(creditsNotificationThreshold: .ten, creditsAddedNotificationsEnabled: true)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 9), settings: [.credits: enabled])
        await service.updateAmountNotificationPreferences(
            for: try #require(balanceSnapshot(credits: 9).creditsMeter), preferences: MeterPreferences()
        )
        await service.updateAmountNotificationPreferences(
            for: try #require(balanceSnapshot(credits: 8).creditsMeter), preferences: enabled
        )
        #expect(await tracker.bodies == ["9 credits remaining."])

        await service.evaluateNotifications(for: balanceSnapshot(credits: 8), settings: [.credits: enabled])
        #expect(await tracker.bodies == ["9 credits remaining.", "8 credits remaining."])
    }

    @Test
    func creditThresholdUsesUnroundedBalanceAndRearmsAfterTopUp() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [.credits: MeterPreferences(creditsNotificationThreshold: .ten)]
        await service.evaluateNotifications(for: balanceSnapshot(credits: 10.4), settings: settings)
        #expect(await tracker.bodies.isEmpty)
        for balance in [9.9, 8, 20, 10, 0] {
            await service.evaluateNotifications(for: balanceSnapshot(credits: balance), settings: settings)
        }
        #expect(await tracker.bodies == ["10 credits remaining.", "10 credits remaining."])
    }

    @Test
    func creditThresholdRearmsWhenChangedOrDisabled() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let snapshot = balanceSnapshot(credits: 9)
        let ten: [UsageMeterID: MeterPreferences] = [.credits: MeterPreferences(creditsNotificationThreshold: .ten)]
        await service.evaluateNotifications(for: snapshot, settings: ten)
        await service.evaluateNotifications(for: snapshot, settings: [.credits: MeterPreferences(creditsNotificationThreshold: .fifty)])
        await service.evaluateNotifications(for: snapshot, settings: [:])
        await service.evaluateNotifications(for: snapshot, settings: ten)
        #expect(await tracker.identifiers == ["codexmeter-credits-threshold-10", "codexmeter-credits-threshold-50", "codexmeter-credits-threshold-10"])
    }

    @Test
    func creditsAddedNotificationIncludesTotalAndDoesNotFireOnFirstObservation() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [.credits: MeterPreferences(creditsAddedNotificationsEnabled: true)]
        for balance in [500.0, 500, 400, 650, 650] {
            await service.evaluateNotifications(for: balanceSnapshot(credits: balance), settings: settings)
        }
        #expect(await tracker.identifiers == ["codexmeter-credits-added"])
        #expect(await tracker.bodies == ["650 credits remaining."])
    }

    @Test(arguments: [(true, false), (false, true), (true, true)])
    func resetChangeTogglesAreIndependent(used: Bool, added: Bool) async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [
            .usageLimitResets: MeterPreferences(resetsUsedNotificationsEnabled: used, resetsAddedNotificationsEnabled: added)
        ]
        for count in [3, 3, 2, 2, 4, 4, 0] {
            await service.evaluateNotifications(for: balanceSnapshot(resets: count), settings: settings)
        }
        var expected: [String] = []
        if used { expected.append("2 usage limit resets remaining. A reset was used or expired.") }
        if added { expected.append("4 usage limit resets remaining.") }
        if used { expected.append("0 usage limit resets remaining. A reset was used or expired.") }
        #expect(await tracker.bodies == expected)
    }

    @Test
    func changesWhileDisabledOrHiddenDoNotProduceCatchUpNotifications() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let enabled = MeterPreferences(creditsAddedNotificationsEnabled: true)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 10), settings: [.credits: enabled])
        await service.evaluateNotifications(for: balanceSnapshot(credits: 20), settings: [:])
        await service.evaluateNotifications(for: balanceSnapshot(credits: 30), settings: [.credits: enabled])
        var hidden = enabled
        hidden.isVisible = false
        await service.evaluateNotifications(for: balanceSnapshot(credits: 50), settings: [.credits: hidden])
        await service.evaluateNotifications(for: balanceSnapshot(credits: 60), settings: [.credits: enabled])
        #expect(await tracker.bodies.isEmpty)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 70), settings: [.credits: enabled])
        #expect(await tracker.bodies == ["70 credits remaining."])
    }

    @Test
    func unlimitedCreditsDoNotTriggerBalanceNotifications() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [.credits: MeterPreferences(creditsNotificationThreshold: .ten, creditsAddedNotificationsEnabled: true)]
        let snapshot = UsageFormatting.snapshot(from: UsageResponse(
            planType: nil, rateLimit: nil, additionalRateLimits: nil,
            credits: CreditsInfo(unlimited: true, balance: .int(0), hasCredits: true)
        ))
        await service.evaluateNotifications(for: snapshot, settings: settings)
        #expect(await tracker.bodies.isEmpty)
    }

    @Test
    func enablingNotificationsRequestsPermission() async throws {
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

        let granted = try await service.requestAuthorizationIfNeeded()

        #expect(granted)
        #expect(await tracker.authorizationRequestCount == 1)
    }

    @Test
    func firesWhenUsageCrossesBelowThreshold() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let settings = notificationSettings(threshold: .twenty)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 25, weeklyRemaining: 50), settings: settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 20, weeklyRemaining: 50), settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20"])
        #expect(await tracker.bodies == ["5 hour limit reached 20% remaining. Resets 2:35 PM (4h 28m)"])
    }

    @Test
    func doesNotRepeatWhileStillBelowThreshold() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let snapshot = makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50)
        let settings = notificationSettings(threshold: .twenty)
        await service.evaluateNotifications(for: snapshot, settings: settings)
        await service.evaluateNotifications(for: snapshot, settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20"])
    }

    @Test(arguments: [false, true])
    func lowAlertsSurviveMissingOrUnavailableMeters(omitted: Bool) async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [
            .secondary: MeterPreferences(notificationThreshold: .twenty),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten)
        ]
        let snapshot = snapshotWithBalances(weeklyRemaining: 15, credits: 9)
        await service.evaluateNotifications(for: snapshot, settings: settings)
        // Absent dynamic meters also have no settings entry in the view model's evaluation.
        await service.evaluateNotifications(for: missingSnapshot(omitted: omitted), settings: omitted ? [:] : settings)
        await service.evaluateNotifications(for: snapshot, settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-secondary-threshold-20", "codexmeter-credits-threshold-10"])
    }

    @Test(arguments: [false, true])
    func balanceChangesCompareWithLastAvailableObservation(omitted: Bool) async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [
            .credits: MeterPreferences(creditsAddedNotificationsEnabled: true),
            .usageLimitResets: MeterPreferences(resetsUsedNotificationsEnabled: true, resetsAddedNotificationsEnabled: true)
        ]
        await service.evaluateNotifications(for: balanceSnapshot(credits: 9, resets: 3), settings: settings)
        await service.evaluateNotifications(for: missingSnapshot(omitted: omitted), settings: omitted ? [:] : settings)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 8, resets: 2), settings: settings)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 8, resets: 2), settings: settings)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 20, resets: 4), settings: settings)

        #expect(await tracker.bodies == [
            "2 usage limit resets remaining. A reset was used or expired.",
            "20 credits remaining.",
            "4 usage limit resets remaining."
        ])
    }

    @Test
    func invalidCreditBalanceAndUnavailablePreferenceUpdatesPreserveLowAlert() async throws {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        var preferences = MeterPreferences(creditsNotificationThreshold: .ten)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 9), settings: [.credits: preferences])
        await service.evaluateNotifications(for: balanceSnapshot(credits: .nan), settings: [.credits: preferences])
        preferences.creditsAddedNotificationsEnabled = true
        await service.updateAmountNotificationPreferences(
            for: try #require(balanceSnapshot().creditsMeter), preferences: preferences
        )
        await service.evaluateNotifications(for: balanceSnapshot(credits: 8), settings: [.credits: preferences])
        #expect(await tracker.bodies == ["9 credits remaining."])
        await service.evaluateNotifications(for: balanceSnapshot(credits: 20), settings: [.credits: preferences])
        #expect(await tracker.bodies == ["9 credits remaining.", "20 credits remaining."])
    }

    @Test
    func lowAlertsPersistAcrossRestartsAndMissingReadings() async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let settings: [UsageMeterID: MeterPreferences] = [
            .secondary: MeterPreferences(notificationThreshold: .twenty),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten)
        ]
        for _ in 0..<3 {
            let service = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
            await service.evaluateNotifications(for: missingSnapshot(omitted: true), settings: [:])
            await service.evaluateNotifications(for: missingSnapshot(omitted: false), settings: settings)
            await service.evaluateNotifications(for: snapshotWithBalances(weeklyRemaining: 15, credits: 9), settings: settings)
        }
        #expect(await tracker.identifiers == ["codexmeter-codex-secondary-threshold-20", "codexmeter-credits-threshold-10"])
    }

    @Test
    func recoveryWithoutAnAlertPersistsAndRearmsLowAlerts() async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let settings: [UsageMeterID: MeterPreferences] = [
            .secondary: MeterPreferences(notificationThreshold: .twenty),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten)
        ]
        let first = makeNotificationService(tracker: tracker, userDefaults: defaults)
        await first.evaluateNotifications(for: snapshotWithBalances(weeklyRemaining: 15, credits: 9), settings: settings)
        await first.evaluateNotifications(for: snapshotWithBalances(weeklyRemaining: 25, credits: 20), settings: settings)
        #expect(await tracker.identifiers.count == 2)
        let restarted = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
        await restarted.evaluateNotifications(for: snapshotWithBalances(weeklyRemaining: 15, credits: 9), settings: settings)
        #expect(await tracker.identifiers.count == 4)
    }

    @Test
    func aNewUsageWindowCanNotifyAfterRestart() async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let settings = notificationSettings(threshold: .twenty)
        for reset in [100.0, 100, 200, 200] {
            let service = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
            await service.evaluateNotifications(
                for: makeSnapshot(fiveHourRemaining: 15, fiveHourReset: Date(timeIntervalSince1970: reset)), settings: settings
            )
        }
        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20", "codexmeter-codex-primary-threshold-20"])
    }

    @Test
    func resetAndBalanceEventsPersistAcrossRestartsAndStillDetectNewChanges() async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let settings: [UsageMeterID: MeterPreferences] = [
            .secondary: MeterPreferences(notificationThreshold: .twenty, resetNotificationsEnabled: true),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten, creditsAddedNotificationsEnabled: true),
            .usageLimitResets: MeterPreferences(resetsUsedNotificationsEnabled: true, resetsAddedNotificationsEnabled: true)
        ]
        let snapshots = [
            snapshotWithBalances(weeklyRemaining: 15, credits: 9, resets: 3),
            snapshotWithBalances(weeklyRemaining: 100, credits: 20, resets: 4),
            snapshotWithBalances(weeklyRemaining: 15, credits: 9, resets: 2)
        ]
        for snapshot in snapshots {
            for _ in 0..<2 {
                let service = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
                await service.evaluateNotifications(for: snapshot, settings: settings)
            }
        }
        #expect(await tracker.bodies == [
            "Weekly limit reached 20% remaining. Resets May 6, 2026 10:30 AM (1d 0h)",
            "9 credits remaining.",
            "Weekly limit reset. 100% remaining. Resets May 6, 2026 10:30 AM (1d 0h)",
            "20 credits remaining.",
            "4 usage limit resets remaining.",
            "Weekly limit reached 20% remaining. Resets May 6, 2026 10:30 AM (1d 0h)",
            "9 credits remaining.",
            "2 usage limit resets remaining. A reset was used or expired."
        ])
    }

    @Test
    func anObservationBelowResetLevelIsRememberedAcrossRestart() async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let settings = notificationSettings(resetNotificationsEnabled: true)
        let first = makeNotificationService(tracker: tracker, userDefaults: defaults)
        await first.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42), settings: settings)
        let restarted = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
        await restarted.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 100), settings: settings)
        #expect(await tracker.identifiers == ["codexmeter-codex-primary-reset"])
    }

    @Test
    func balancePreferenceUpdatesPersistWithoutRepeatingLowAlerts() async throws {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        var preferences = MeterPreferences(creditsNotificationThreshold: .ten)
        let first = makeNotificationService(tracker: tracker, userDefaults: defaults)
        await first.evaluateNotifications(for: balanceSnapshot(credits: 9), settings: [.credits: preferences])
        preferences.creditsAddedNotificationsEnabled = true
        await first.updateAmountNotificationPreferences(
            for: try #require(balanceSnapshot(credits: 9).creditsMeter), preferences: preferences
        )
        let restarted = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
        await restarted.evaluateNotifications(for: balanceSnapshot(credits: 8), settings: [.credits: preferences])
        await restarted.evaluateNotifications(for: balanceSnapshot(credits: 20), settings: [.credits: preferences])
        #expect(await tracker.bodies == ["9 credits remaining.", "20 credits remaining."])
    }

    @Test(arguments: [UNAuthorizationStatus.denied, .notDetermined])
    func startingWithoutPermissionDoesNotEraseHistory(status: UNAuthorizationStatus) async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let settings: [UsageMeterID: MeterPreferences] = [
            .secondary: MeterPreferences(notificationThreshold: .twenty),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten)
        ]
        let snapshot = snapshotWithBalances(weeklyRemaining: 15, credits: 9)
        await makeNotificationService(tracker: tracker, userDefaults: defaults)
            .evaluateNotifications(for: snapshot, settings: settings)
        let denied = NotificationService(
            authorizationRequester: { false }, authorizationStatusProvider: { status },
            requestDeliverer: { request in await tracker.record(request: request) },
            userDefaults: UserDefaults(suiteName: suite)!
        )
        await denied.evaluateNotifications(for: snapshot, settings: [:])
        await makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
            .evaluateNotifications(for: snapshot, settings: settings)
        #expect(await tracker.identifiers.count == 2)
    }

    @Test
    func invalidStoredHistoryDoesNotPreventNotificationsOrRecovery() async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid history".utf8), forKey: "notificationHistory.v1")
        let tracker = NotificationTracker()
        let settings = notificationSettings(threshold: .twenty)
        for _ in 0..<2 {
            let service = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
            await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 15), settings: settings)
        }
        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20"])
    }

    @Test
    func countdownResetTimeDriftDoesNotRepeatThresholdAlert() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings = notificationSettings(threshold: .twenty)
        for drift in [0.0, 0.25, 30, 59] {
            let window = UsageWindow(usedPercent: 85, limitWindowSeconds: 18_000, resetAfterSeconds: 7_200, resetAt: nil)
            let snapshot = UsageFormatting.snapshot(from: UsageResponse(
                planType: nil, rateLimit: RateLimitInfo(primaryWindow: window, secondaryWindow: nil),
                additionalRateLimits: nil, credits: nil
            ), now: Date(timeIntervalSince1970: 1_000 + drift))
            await service.evaluateNotifications(for: snapshot, settings: settings)
        }
        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20"])
    }

    @Test
    func temporarilyMissingResetDateDoesNotRepeatThresholdAlert() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings = notificationSettings(threshold: .twenty)
        for resetAt in [10_000, nil, 10_000, 20_000] as [Double?] {
            let window = UsageWindow(usedPercent: 85, limitWindowSeconds: 18_000, resetAfterSeconds: nil, resetAt: resetAt)
            let snapshot = UsageFormatting.snapshot(from: UsageResponse(
                planType: nil, rateLimit: RateLimitInfo(primaryWindow: window, secondaryWindow: nil),
                additionalRateLimits: nil, credits: nil
            ))
            await service.evaluateNotifications(for: snapshot, settings: settings)
        }
        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20", "codexmeter-codex-primary-threshold-20"])
    }

    @Test(arguments: [false, true])
    func overlappingEvaluationsDoNotRepeatAlerts(resetAlert: Bool) async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let delivery = BlockingNotificationDelivery()
        let service = NotificationService(
            authorizationRequester: { true }, authorizationStatusProvider: { .authorized },
            requestDeliverer: { request in
                await tracker.record(request: request)
                await delivery.suspendFirstDelivery()
            },
            userDefaults: defaults
        )
        let settings = notificationSettings(threshold: resetAlert ? nil : .twenty, resetNotificationsEnabled: resetAlert)
        if resetAlert {
            await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42), settings: settings)
        }
        let snapshot = makeSnapshot(fiveHourRemaining: resetAlert ? 100 : 15)
        let first = Task { await service.evaluateNotifications(for: snapshot, settings: settings) }
        await delivery.waitUntilSuspended()
        await service.evaluateNotifications(for: snapshot, settings: settings)
        // Even a new instance sees the reservation while the original delivery
        // is suspended, so termination during delivery cannot replay the event.
        let restarted = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
        await restarted.evaluateNotifications(for: snapshot, settings: settings)
        await delivery.resume()
        await first.value

        #expect(await tracker.identifiers == [resetAlert ? "codexmeter-codex-primary-reset" : "codexmeter-codex-primary-threshold-20"])
    }

    @Test(arguments: [false, true])
    func suspendedDeliveryDoesNotOverwriteNewerObservation(resetAlert: Bool) async {
        let tracker = NotificationTracker()
        let delivery = BlockingNotificationDelivery()
        let service = NotificationService(
            authorizationRequester: { true }, authorizationStatusProvider: { .authorized },
            requestDeliverer: { request in
                await tracker.record(request: request)
                await delivery.suspendFirstDelivery()
            }
        )
        let settings = notificationSettings(threshold: resetAlert ? nil : .twenty, resetNotificationsEnabled: resetAlert)
        let rearmedSnapshot = makeSnapshot(fiveHourRemaining: resetAlert ? 42 : 25)
        if resetAlert {
            await service.evaluateNotifications(for: rearmedSnapshot, settings: settings)
        }
        let snapshot = makeSnapshot(fiveHourRemaining: resetAlert ? 100 : 15)
        let first = Task { await service.evaluateNotifications(for: snapshot, settings: settings) }
        await delivery.waitUntilSuspended()
        await service.evaluateNotifications(for: rearmedSnapshot, settings: settings)
        await delivery.resume()
        await first.value
        await service.evaluateNotifications(for: snapshot, settings: settings)

        #expect(await tracker.identifiers.count == 2)
    }

    @Test
    func differentNotificationEventsHaveSeparateIdentifiers() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [
            .secondary: MeterPreferences(notificationThreshold: .twenty, resetNotificationsEnabled: true),
            .credits: MeterPreferences(creditsNotificationThreshold: .ten, creditsAddedNotificationsEnabled: true),
            .usageLimitResets: MeterPreferences(resetsUsedNotificationsEnabled: true, resetsAddedNotificationsEnabled: true)
        ]
        await service.evaluateNotifications(for: snapshotWithBalances(weeklyRemaining: 15, credits: 9, resets: 3), settings: settings)
        await service.evaluateNotifications(for: snapshotWithBalances(weeklyRemaining: 100, credits: 20, resets: 2), settings: settings)
        await service.evaluateNotifications(for: snapshotWithBalances(weeklyRemaining: 100, credits: 20, resets: 4), settings: settings)
        let identifiers = await tracker.identifiers
        #expect(identifiers.count == 6)
        #expect(Set(identifiers).count == 6)
    }

    @Test
    func becomesEligibleAgainAfterReset() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let settings = notificationSettings(threshold: .twenty)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50, fiveHourReset: .init(timeIntervalSince1970: 100)), settings: settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50, fiveHourReset: .init(timeIntervalSince1970: 200)), settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20", "codexmeter-codex-primary-threshold-20"])
    }

    @Test
    func tracksFiveHourAndWeeklyWindowsIndependently() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(
            for: makeSnapshot(fiveHourRemaining: 10, weeklyRemaining: 10),
            settings: notificationSettings(threshold: .twenty, includesSecondary: true)
        )

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-20", "codexmeter-codex-secondary-threshold-20"])
    }

    @Test
    func becomesEligibleAgainWhenThresholdChanges() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let snapshot = makeSnapshot(fiveHourRemaining: 9, weeklyRemaining: 50)
        await service.evaluateNotifications(for: snapshot, settings: notificationSettings(threshold: .ten))
        await service.evaluateNotifications(for: snapshot, settings: notificationSettings(threshold: .twenty))

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-10", "codexmeter-codex-primary-threshold-20"])
    }

    @Test
    func reconcilesThresholdChangesDuringEvaluation() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let snapshot = makeSnapshot(fiveHourRemaining: 9, weeklyRemaining: 50)
        await service.evaluateNotifications(for: snapshot, settings: notificationSettings(threshold: .ten))
        await service.evaluateNotifications(for: snapshot, settings: notificationSettings(threshold: .twenty))

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-threshold-10", "codexmeter-codex-primary-threshold-20"])
    }

    @Test
    func resetNotificationsFireWhenUsageReturnsToNinetyNinePercent() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let settings = notificationSettings(resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), settings: settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 50), settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-reset"])
        #expect(await tracker.bodies == ["5 hour limit reset. 99% remaining. Resets 2:35 PM (4h 28m)"])
    }

    @Test
    func resetNotificationsFireWhenUsageReturnsToOneHundredPercent() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let settings = notificationSettings(resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), settings: settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 100, weeklyRemaining: 50), settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-reset"])
    }

    @Test
    func resetNotificationsDoNotFireOnFirstObservationAtResetLevel() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(
            for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 100),
            settings: notificationSettings(resetNotificationsEnabled: true)
        )

        #expect(await tracker.identifiers == [])
    }

    @Test
    func resetNotificationsTrackFiveHourAndWeeklyWindowsIndependently() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let settings = notificationSettings(resetNotificationsEnabled: true, includesSecondary: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), settings: settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 99), settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-reset", "codexmeter-codex-secondary-reset"])
    }

    @Test
    func resetNotificationsDoNotRepeatWhileStillAtResetLevel() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let settings = notificationSettings(resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), settings: settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 50), settings: settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 100, weeklyRemaining: 50), settings: settings)

        #expect(await tracker.identifiers == ["codexmeter-codex-primary-reset"])
    }

    @Test(arguments: [false, true])
    func resetNotificationsCompareWithLastAvailableObservation(omitted: Bool) async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings = notificationSettings(resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42), settings: settings)
        await service.evaluateNotifications(for: missingSnapshot(omitted: omitted), settings: omitted ? [:] : settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99), settings: settings)
        await service.evaluateNotifications(for: missingSnapshot(omitted: omitted), settings: omitted ? [:] : settings)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 100), settings: settings)
        #expect(await tracker.identifiers == ["codexmeter-codex-primary-reset"])
    }

    @Test
    func disabledMeterDoesNotNotify() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let settings: [UsageMeterID: MeterPreferences] = [
            .primary: MeterPreferences(isVisible: false, notificationThreshold: .twenty)
        ]

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 10), settings: settings)

        #expect(await tracker.identifiers.isEmpty)
    }

    @Test
    func dynamicMeterNotificationIdentifiersDoNotCollideAfterEncoding() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let hyphenatedID = UsageMeterID.additional(
            feature: "codex-feature",
            slot: .primary
        )
        let underscoredID = UsageMeterID.additional(
            feature: "codex_feature",
            slot: .primary
        )
        let meters = [hyphenatedID, underscoredID].map { meterID in
            UsageMeterViewData(
                id: meterID,
                kind: .rateLimit,
                title: "Additional usage",
                valueText: "10% remaining",
                resetText: nil,
                remainingPercent: 10,
                level: .critical,
                resetDate: Date(timeIntervalSince1970: 100),
                isAvailable: true
            )
        }
        let snapshot = UsageSnapshot(
            meters: meters,
            lastUpdated: Date(),
            warningMessage: nil
        )
        let preferences = MeterPreferences(notificationThreshold: .twenty)
        let settings = [
            hyphenatedID: preferences,
            underscoredID: preferences
        ]

        await service.evaluateNotifications(for: snapshot, settings: settings)

        let identifiers = await tracker.identifiers
        #expect(identifiers.count == 2)
        #expect(Set(identifiers).count == 2)
    }

    @Test
    func dynamicMeterHistorySurvivesRestart() async {
        let suite = "NotificationHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tracker = NotificationTracker()
        let meterID = UsageMeterID.additional(feature: "codex/feature.with-punctuation", slot: .secondary)
        let snapshot = UsageSnapshot(meters: [UsageMeterViewData(
            id: meterID, kind: .rateLimit, title: "Additional usage", valueText: "15% remaining",
            resetText: nil, remainingPercent: 15, level: .critical,
            resetDate: Date(timeIntervalSince1970: 100), isAvailable: true
        )], lastUpdated: Date(), warningMessage: nil)
        for _ in 0..<2 {
            let service = makeNotificationService(tracker: tracker, userDefaults: UserDefaults(suiteName: suite)!)
            await service.evaluateNotifications(for: snapshot, settings: [meterID: MeterPreferences(notificationThreshold: .twenty)])
        }
        #expect(await tracker.identifiers.count == 1)
    }
}

private actor BlockingNotificationDelivery {
    private var hasDelivered = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func suspendFirstDelivery() async {
        guard !hasDelivered else { return }
        hasDelivered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilSuspended() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private func missingSnapshot(omitted: Bool) -> UsageSnapshot {
    omitted
        ? UsageSnapshot(meters: [], lastUpdated: Date(), warningMessage: nil)
        : balanceSnapshot()
}

private func snapshotWithBalances(weeklyRemaining: Int, credits: Double, resets: Int? = nil) -> UsageSnapshot {
    UsageSnapshot(
        meters: makeSnapshot(weeklyRemaining: weeklyRemaining).meters.filter { $0.kind == .rateLimit }
            + balanceSnapshot(credits: credits, resets: resets).meters.filter { $0.kind != .rateLimit },
        lastUpdated: Date(), warningMessage: nil
    )
}

private func balanceSnapshot(credits: Double? = nil, resets: Int? = nil) -> UsageSnapshot {
    UsageFormatting.snapshot(from: UsageResponse(
        planType: nil,
        rateLimit: nil,
        additionalRateLimits: nil,
        credits: credits.map { CreditsInfo(unlimited: false, balance: .double($0), hasCredits: true) },
        rateLimitResetCredits: resets.map { RateLimitResetCreditsInfo(availableCount: $0) }
    ))
}

private func notificationSettings(
    threshold: NotificationThreshold? = nil,
    resetNotificationsEnabled: Bool = false,
    includesSecondary: Bool = false
) -> [UsageMeterID: MeterPreferences] {
    let preferences = MeterPreferences(
        notificationThreshold: threshold,
        resetNotificationsEnabled: resetNotificationsEnabled
    )
    var settings: [UsageMeterID: MeterPreferences] = [.primary: preferences]
    if includesSecondary {
        settings[.secondary] = preferences
    }
    return settings
}
