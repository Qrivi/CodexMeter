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

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 25, weeklyRemaining: 50), threshold: .twenty, resetNotificationsEnabled: false)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 20, weeklyRemaining: 50), threshold: .twenty, resetNotificationsEnabled: false)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-threshold-20"])
        #expect(await tracker.bodies == ["5 hour usage limit reached 20% remaining. Resets 2:35 PM (4h 28m)"])
    }

    @Test
    func doesNotRepeatWhileStillBelowThreshold() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let snapshot = makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50)
        await service.evaluateNotifications(for: snapshot, threshold: .twenty, resetNotificationsEnabled: false)
        await service.evaluateNotifications(for: snapshot, threshold: .twenty, resetNotificationsEnabled: false)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-threshold-20"])
    }

    @Test
    func becomesEligibleAgainAfterReset() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50, fiveHourReset: .init(timeIntervalSince1970: 100)), threshold: .twenty, resetNotificationsEnabled: false)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 15, weeklyRemaining: 50, fiveHourReset: .init(timeIntervalSince1970: 200)), threshold: .twenty, resetNotificationsEnabled: false)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-threshold-20", "codexmeter-fiveHour-threshold-20"])
    }

    @Test
    func tracksFiveHourAndWeeklyWindowsIndependently() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 10, weeklyRemaining: 10), threshold: .twenty, resetNotificationsEnabled: false)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-threshold-20", "codexmeter-weekly-threshold-20"])
    }

    @Test
    func becomesEligibleAgainWhenThresholdChanges() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let snapshot = makeSnapshot(fiveHourRemaining: 9, weeklyRemaining: 50)
        await service.updateThreshold(.ten)
        await service.evaluateNotifications(for: snapshot, threshold: .ten, resetNotificationsEnabled: false)
        await service.updateThreshold(.twenty)
        await service.evaluateNotifications(for: snapshot, threshold: .twenty, resetNotificationsEnabled: false)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-threshold-10", "codexmeter-fiveHour-threshold-20"])
    }

    @Test
    func reconcilesThresholdChangesDuringEvaluation() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        let snapshot = makeSnapshot(fiveHourRemaining: 9, weeklyRemaining: 50)
        await service.evaluateNotifications(for: snapshot, threshold: .ten, resetNotificationsEnabled: false)
        await service.evaluateNotifications(for: snapshot, threshold: .twenty, resetNotificationsEnabled: false)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-threshold-10", "codexmeter-fiveHour-threshold-20"])
    }

    @Test
    func resetNotificationsFireWhenUsageReturnsToNinetyNinePercent() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-reset"])
        #expect(await tracker.bodies == ["5 hour usage limit reset. 99% remaining. Resets 2:35 PM (4h 28m)"])
    }

    @Test
    func resetNotificationsFireWhenUsageReturnsToOneHundredPercent() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 100, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-reset"])
    }

    @Test
    func resetNotificationsDoNotFireOnFirstObservationAtResetLevel() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 100), threshold: nil, resetNotificationsEnabled: true)

        #expect(await tracker.identifiers == [])
    }

    @Test
    func resetNotificationsTrackFiveHourAndWeeklyWindowsIndependently() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 99), threshold: nil, resetNotificationsEnabled: true)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-reset", "codexmeter-weekly-reset"])
    }

    @Test
    func resetNotificationsDoNotRepeatWhileStillAtResetLevel() async {
        let tracker = NotificationTracker()
        let service = makeNotificationService(tracker: tracker)

        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 42, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 99, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)
        await service.evaluateNotifications(for: makeSnapshot(fiveHourRemaining: 100, weeklyRemaining: 50), threshold: nil, resetNotificationsEnabled: true)

        #expect(await tracker.identifiers == ["codexmeter-fiveHour-reset"])
    }
}
