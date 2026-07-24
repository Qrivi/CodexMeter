import Foundation
@preconcurrency import UserNotifications

actor NotificationService: NotificationScheduling {
    private struct ThresholdNotificationState: Sendable {
        var threshold: NotificationThreshold?
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
    private var thresholdStateByMeter: [UsageMeterID: ThresholdNotificationState] = [:]
    private var resetStateByMeter: [UsageMeterID: ResetNotificationState] = [:]

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

    func evaluateNotifications(
        for snapshot: UsageSnapshot,
        settings: [UsageMeterID: MeterPreferences]
    ) async {
        let enabledMeters = snapshot.meters.filter { meter in
            meter.isAvailable
                && meter.supportsNotifications
                && (settings[meter.id] ?? MeterPreferences()).isVisible
        }
        let enabledIDs = Set(enabledMeters.map(\.id))
        thresholdStateByMeter = thresholdStateByMeter.filter { enabledIDs.contains($0.key) }
        resetStateByMeter = resetStateByMeter.filter { enabledIDs.contains($0.key) }

        guard enabledMeters.contains(where: { meter in
            let preferences = settings[meter.id] ?? MeterPreferences()
            return preferences.notificationThreshold != nil || preferences.resetNotificationsEnabled
        }) else {
            return
        }

        let status = await authorizationStatusProvider()
        guard [.authorized, .provisional].contains(status) else {
            return
        }

        for meter in enabledMeters {
            let preferences = settings[meter.id] ?? MeterPreferences()
            await evaluate(
                meter: meter,
                threshold: preferences.notificationThreshold,
                resetNotificationsEnabled: preferences.resetNotificationsEnabled
            )
        }
    }

    private func evaluate(
        meter: UsageMeterViewData,
        threshold: NotificationThreshold?,
        resetNotificationsEnabled: Bool
    ) async {
        guard let remainingPercent = meter.remainingPercent else {
            return
        }

        if let threshold {
            await evaluateThresholdNotification(
                meter: meter,
                remainingPercent: remainingPercent,
                threshold: threshold
            )
        }

        if resetNotificationsEnabled {
            await evaluateResetNotification(meter: meter, remainingPercent: remainingPercent)
        }
    }

    private func evaluateThresholdNotification(
        meter: UsageMeterViewData,
        remainingPercent: Int,
        threshold: NotificationThreshold
    ) async {
        var notificationState = thresholdStateByMeter[meter.id]
            ?? ThresholdNotificationState(threshold: threshold)

        if notificationState.threshold != threshold || notificationState.resetDate != meter.resetDate {
            notificationState = ThresholdNotificationState(
                threshold: threshold,
                resetDate: meter.resetDate,
                hasNotified: false
            )
        }

        if remainingPercent > threshold.rawValue {
            notificationState.hasNotified = false
            notificationState.resetDate = meter.resetDate
            thresholdStateByMeter[meter.id] = notificationState
            return
        }

        guard notificationState.hasNotified == false else {
            thresholdStateByMeter[meter.id] = notificationState
            return
        }

        let body = bodyText(
            prefix: "\(meter.title) reached \(threshold.rawValue)% remaining.",
            resetText: meter.resetText
        )

        let content = UNMutableNotificationContent()
        content.title = "\(meter.title) is low"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codexmeter-\(identifierComponent(for: meter.id))-threshold-\(threshold.rawValue)",
            content: content,
            trigger: nil
        )

        await requestDeliverer(request)
        notificationState.hasNotified = true
        notificationState.resetDate = meter.resetDate
        thresholdStateByMeter[meter.id] = notificationState
    }

    private func evaluateResetNotification(meter: UsageMeterViewData, remainingPercent: Int) async {
        var notificationState = resetStateByMeter[meter.id] ?? ResetNotificationState()

        guard remainingPercent >= Self.resetRemainingPercent else {
            notificationState.hasSeenBelowResetLevel = true
            notificationState.hasNotifiedAtResetLevel = false
            resetStateByMeter[meter.id] = notificationState
            return
        }

        defer {
            resetStateByMeter[meter.id] = notificationState
        }

        guard notificationState.hasSeenBelowResetLevel,
              notificationState.hasNotifiedAtResetLevel == false else {
            return
        }

        let body = bodyText(
            prefix: "\(meter.title) reset. \(remainingPercent)% remaining.",
            resetText: meter.resetText
        )

        let content = UNMutableNotificationContent()
        content.title = "\(meter.title) reset"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codexmeter-\(identifierComponent(for: meter.id))-reset",
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

    private func identifierComponent(for meterID: UsageMeterID) -> String {
        meterID.rawValue
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }
    }
}
