import Foundation
@preconcurrency import UserNotifications

actor NotificationService: NotificationScheduling {
    private struct ThresholdNotificationState: Sendable {
        var resetDate: Date?
        var hasNotified = false
    }

    private struct ResetNotificationState: Sendable {
        var hasSeenBelowResetLevel = false
        var hasNotifiedAtResetLevel = false
    }

    nonisolated private static let resetRemainingPercent = 99

    private let authorizationRequester: @Sendable () async -> Bool
    private let authorizationStatusProvider: @Sendable () async -> UNAuthorizationStatus
    private let requestDeliverer: @Sendable (UNNotificationRequest) async -> Void
    private var currentThreshold: NotificationThreshold?
    private var thresholdStateByWindow: [UsageWindowKind: ThresholdNotificationState] = [:]
    private var resetStateByWindow: [UsageWindowKind: ResetNotificationState] = [:]

    init(center: UNUserNotificationCenter = .current()) {
        self.authorizationRequester = {
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        }

        self.authorizationStatusProvider = {
            await center.notificationSettings().authorizationStatus
        }

        self.requestDeliverer = { request in
            try? await center.add(request)
        }
    }

    init(
        authorizationRequester: @escaping @Sendable () async -> Bool,
        authorizationStatusProvider: @escaping @Sendable () async -> UNAuthorizationStatus,
        requestDeliverer: @escaping @Sendable (UNNotificationRequest) async -> Void
    ) {
        self.authorizationRequester = authorizationRequester
        self.authorizationStatusProvider = authorizationStatusProvider
        self.requestDeliverer = requestDeliverer
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatusProvider()

        switch status {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return await authorizationRequester()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func updateThreshold(_ threshold: NotificationThreshold?) async {
        reconcileThreshold(threshold)
    }

    func evaluateNotifications(
        for snapshot: UsageSnapshot,
        threshold: NotificationThreshold?,
        resetNotificationsEnabled: Bool
    ) async {
        reconcileThreshold(threshold)

        guard threshold != nil || resetNotificationsEnabled else {
            return
        }

        let status = await authorizationStatusProvider()
        guard [.authorized, .provisional].contains(status) else {
            return
        }

        await evaluate(
            section: snapshot.fiveHourSection,
            threshold: threshold,
            resetNotificationsEnabled: resetNotificationsEnabled
        )
        await evaluate(
            section: snapshot.weeklySection,
            threshold: threshold,
            resetNotificationsEnabled: resetNotificationsEnabled
        )
    }

    private func reconcileThreshold(_ threshold: NotificationThreshold?) {
        if threshold != currentThreshold {
            thresholdStateByWindow.removeAll()
        }

        currentThreshold = threshold
    }

    private func evaluate(
        section: UsageSectionViewData,
        threshold: NotificationThreshold?,
        resetNotificationsEnabled: Bool
    ) async {
        guard let remainingPercent = section.remainingPercent else {
            return
        }

        if let threshold {
            await evaluateThresholdNotification(
                section: section,
                remainingPercent: remainingPercent,
                threshold: threshold
            )
        }

        if resetNotificationsEnabled {
            await evaluateResetNotification(section: section, remainingPercent: remainingPercent)
        }
    }

    private func evaluateThresholdNotification(
        section: UsageSectionViewData,
        remainingPercent: Int,
        threshold: NotificationThreshold
    ) async {
        var notificationState = thresholdStateByWindow[section.windowKind] ?? ThresholdNotificationState()

        if notificationState.resetDate != section.resetDate {
            notificationState = ThresholdNotificationState(resetDate: section.resetDate, hasNotified: false)
        }

        if remainingPercent > threshold.rawValue {
            notificationState.hasNotified = false
            notificationState.resetDate = section.resetDate
            thresholdStateByWindow[section.windowKind] = notificationState
            return
        }

        guard notificationState.hasNotified == false else {
            thresholdStateByWindow[section.windowKind] = notificationState
            return
        }

        let body = bodyText(
            prefix: "\(section.title) reached \(threshold.rawValue)% remaining.",
            resetText: section.resetText
        )

        let content = UNMutableNotificationContent()
        content.title = section.windowKind.limitNotificationTitle
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codexmeter-\(section.windowKind.rawValue)-threshold-\(threshold.rawValue)",
            content: content,
            trigger: nil
        )

        await requestDeliverer(request)
        notificationState.hasNotified = true
        notificationState.resetDate = section.resetDate
        thresholdStateByWindow[section.windowKind] = notificationState
    }

    private func evaluateResetNotification(section: UsageSectionViewData, remainingPercent: Int) async {
        var notificationState = resetStateByWindow[section.windowKind] ?? ResetNotificationState()

        guard remainingPercent >= Self.resetRemainingPercent else {
            notificationState.hasSeenBelowResetLevel = true
            notificationState.hasNotifiedAtResetLevel = false
            resetStateByWindow[section.windowKind] = notificationState
            return
        }

        defer {
            resetStateByWindow[section.windowKind] = notificationState
        }

        guard notificationState.hasSeenBelowResetLevel,
              notificationState.hasNotifiedAtResetLevel == false else {
            return
        }

        let body = bodyText(
            prefix: "\(section.title) reset. \(remainingPercent)% remaining.",
            resetText: section.resetText
        )

        let content = UNMutableNotificationContent()
        content.title = section.windowKind.resetNotificationTitle
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codexmeter-\(section.windowKind.rawValue)-reset",
            content: content,
            trigger: nil
        )

        await requestDeliverer(request)
        notificationState.hasNotifiedAtResetLevel = true
    }

    private func bodyText(prefix: String, resetText: String?) -> String {
        if let resetText {
            return "\(prefix) \(resetText)"
        }

        return prefix
    }
}
