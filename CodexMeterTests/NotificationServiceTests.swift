import Foundation
import Testing
import UserNotifications
@testable import CodexMeter

@MainActor
struct NotificationServiceTests {
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
    func changesWhileDisabledHiddenOrUnavailableDoNotProduceCatchUpNotifications() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)
        let enabled = MeterPreferences(creditsAddedNotificationsEnabled: true)
        await service.evaluateNotifications(for: balanceSnapshot(credits: 10), settings: [.credits: enabled])
        await service.evaluateNotifications(for: balanceSnapshot(credits: 20), settings: [:])
        await service.evaluateNotifications(for: balanceSnapshot(credits: 30), settings: [.credits: enabled])
        await service.evaluateNotifications(for: balanceSnapshot(), settings: [.credits: enabled])
        await service.evaluateNotifications(for: balanceSnapshot(credits: 40), settings: [.credits: enabled])
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
