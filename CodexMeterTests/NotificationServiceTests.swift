import Foundation
import Testing
import UserNotifications
@testable import CodexMeter

@MainActor
struct NotificationServiceTests {
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
