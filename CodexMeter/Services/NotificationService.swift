import Foundation
@preconcurrency import UserNotifications

actor NotificationService: NotificationScheduling {
    private struct ThresholdNotificationState: Codable, Sendable {
        var threshold: NotificationThreshold?
        var resetDate: Date?
        var hasNotified = false
    }

    private struct ResetNotificationState: Codable, Sendable {
        var hasSeenBelowResetLevel = false
        var hasNotifiedAtResetLevel = false
    }

    private struct AmountNotificationState: Codable, Sendable {
        var amount: Double
        var preferences: MeterPreferences
        var hasNotifiedLow = false
    }

    private struct NotificationHistory: Codable, Sendable {
        var thresholds: [UsageMeterID: ThresholdNotificationState]
        var resets: [UsageMeterID: ResetNotificationState]
        var amounts: [UsageMeterID: AmountNotificationState]
    }

    nonisolated private static let historyKey = "notificationHistory.v1"
    nonisolated private static let resetRemainingPercent = 99
    // Derived reset times can vary slightly with request latency and whole-second countdowns.
    nonisolated private static let resetDateTolerance: TimeInterval = 60

    private let authorizationRequester: @Sendable () async throws -> Bool
    private let authorizationStatusProvider: @Sendable () async -> UNAuthorizationStatus
    private let requestDeliverer: @Sendable (UNNotificationRequest) async -> Void
    private let userDefaults: UserDefaults?
    private var thresholdStateByMeter: [UsageMeterID: ThresholdNotificationState] = [:]
    private var resetStateByMeter: [UsageMeterID: ResetNotificationState] = [:]
    private var amountStateByMeter: [UsageMeterID: AmountNotificationState] = [:]

    init(center: UNUserNotificationCenter = .current(), userDefaults: UserDefaults = .standard) {
        self.init(
            authorizationRequester: {
                try await center.requestAuthorization(options: [.alert, .sound])
            },
            authorizationStatusProvider: {
                await center.notificationSettings().authorizationStatus
            },
            requestDeliverer: { request in
                try? await center.add(request)
            },
            userDefaults: userDefaults
        )
    }

    init(
        authorizationRequester: @escaping @Sendable () async throws -> Bool,
        authorizationStatusProvider: @escaping @Sendable () async -> UNAuthorizationStatus,
        requestDeliverer: @escaping @Sendable (UNNotificationRequest) async -> Void,
        userDefaults: UserDefaults? = nil
    ) {
        self.authorizationRequester = authorizationRequester
        self.authorizationStatusProvider = authorizationStatusProvider
        self.requestDeliverer = requestDeliverer
        self.userDefaults = userDefaults
        if let data = userDefaults?.data(forKey: Self.historyKey),
           let history = try? JSONDecoder().decode(NotificationHistory.self, from: data) {
            thresholdStateByMeter = history.thresholds
            resetStateByMeter = history.resets
            amountStateByMeter = history.amounts
        }
    }

    private func persistHistory() {
        guard let userDefaults else { return }
        let history = NotificationHistory(
            thresholds: thresholdStateByMeter,
            resets: resetStateByMeter,
            amounts: amountStateByMeter
        )
        guard let data = try? JSONEncoder().encode(history) else { return }
        userDefaults.set(data, forKey: Self.historyKey)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await authorizationStatusProvider()
    }

    func requestAuthorizationIfNeeded() async throws -> Bool {
        let status = await authorizationStatusProvider()

        switch status {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return try await authorizationRequester()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func updateAmountNotificationPreferences(
        for meter: UsageMeterViewData,
        preferences: MeterPreferences
    ) {
        defer { persistHistory() }
        guard preferences.isVisible,
              amountNotificationsEnabled(for: meter, preferences: preferences) else {
            amountStateByMeter[meter.id] = nil
            return
        }

        guard meter.isAvailable, let amount = meter.remainingAmount, amount.isFinite else {
            if var state = amountStateByMeter[meter.id] {
                if state.preferences.creditsNotificationThreshold != preferences.creditsNotificationThreshold {
                    state.hasNotifiedLow = false
                }
                state.preferences = preferences
                amountStateByMeter[meter.id] = state
            }
            return
        }

        var state = amountStateByMeter[meter.id]
            ?? AmountNotificationState(amount: amount, preferences: preferences)
        if state.preferences.creditsNotificationThreshold != preferences.creditsNotificationThreshold {
            state.hasNotifiedLow = false
        }
        state.amount = amount
        state.preferences = preferences
        amountStateByMeter[meter.id] = state
    }

    private func amountNotificationsEnabled(for meter: UsageMeterViewData, preferences: MeterPreferences) -> Bool {
        switch meter.kind {
        case .rateLimit:
            false
        case .credits:
            preferences.creditsNotificationThreshold != nil || preferences.creditsAddedNotificationsEnabled
        case .usageLimitResets:
            preferences.resetsUsedNotificationsEnabled || preferences.resetsAddedNotificationsEnabled
        }
    }

    func evaluateNotifications(
        for snapshot: UsageSnapshot,
        settings: [UsageMeterID: MeterPreferences]
    ) async {
        // A denied or not-yet-known permission is not a new notification event.
        // Preserve history so restoring permission cannot replay delivered alerts.
        let status = await authorizationStatusProvider()
        guard [.authorized, .provisional].contains(status) else { return }

        defer { persistHistory() }
        // Only explicit preference changes clear history. Missing or unavailable
        // observations must leave the last successful observation intact.
        for meter in snapshot.meters {
            let preferences = settings[meter.id] ?? MeterPreferences()
            if !preferences.isVisible || preferences.notificationThreshold == nil {
                thresholdStateByMeter[meter.id] = nil
            }
            if !preferences.isVisible || !preferences.resetNotificationsEnabled {
                resetStateByMeter[meter.id] = nil
            }
            if !preferences.isVisible || !amountNotificationsEnabled(for: meter, preferences: preferences) {
                amountStateByMeter[meter.id] = nil
            }
        }

        let enabledMeters = snapshot.meters.filter { meter in
            meter.isAvailable
                && meter.supportsNotifications
                && (settings[meter.id] ?? MeterPreferences()).isVisible
        }
        let amountEnabledIDs = Set(enabledMeters.filter { meter in
            let preferences = settings[meter.id] ?? MeterPreferences()
            return amountNotificationsEnabled(for: meter, preferences: preferences)
        }.map(\.id))

        guard enabledMeters.contains(where: { meter in
            let preferences = settings[meter.id] ?? MeterPreferences()
            return preferences.notificationThreshold != nil || preferences.resetNotificationsEnabled
                || amountEnabledIDs.contains(meter.id)
        }) else {
            return
        }

        for meter in enabledMeters {
            let preferences = settings[meter.id] ?? MeterPreferences()
            if meter.kind == .rateLimit {
                await evaluate(
                    meter: meter,
                    threshold: preferences.notificationThreshold,
                    resetNotificationsEnabled: preferences.resetNotificationsEnabled
                )
            } else if amountEnabledIDs.contains(meter.id) {
                await evaluateAmountNotifications(meter: meter, preferences: preferences)
            }
        }
    }

    private func evaluateAmountNotifications(meter: UsageMeterViewData, preferences: MeterPreferences) async {
        guard let amount = meter.remainingAmount, amount.isFinite else {
            return
        }
        let previous = amountStateByMeter[meter.id]
        var state = AmountNotificationState(amount: amount, preferences: preferences)
        var messages: [(event: String, title: String, body: String)] = []

        if meter.kind == .credits {
            if let threshold = preferences.creditsNotificationThreshold {
                state.hasNotifiedLow = previous?.preferences.creditsNotificationThreshold == threshold
                    && previous?.hasNotifiedLow == true
                if amount > Double(threshold.rawValue) {
                    state.hasNotifiedLow = false
                } else if state.hasNotifiedLow == false {
                    messages.append(("threshold-\(threshold.rawValue)", "Credits are low", "\(meter.valueText) credits remaining."))
                    state.hasNotifiedLow = true
                }
            }
            if let previous, amount > previous.amount,
               preferences.creditsAddedNotificationsEnabled,
               previous.preferences.creditsAddedNotificationsEnabled {
                messages.append(("added", "Credits added", "\(meter.valueText) credits remaining."))
            }
        } else if let previous {
            if amount < previous.amount,
               preferences.resetsUsedNotificationsEnabled,
               previous.preferences.resetsUsedNotificationsEnabled {
                messages.append(("decreased", "Usage limit reset count decreased", "\(meter.valueText) usage limit resets remaining. A reset was used or expired."))
            } else if amount > previous.amount,
                      preferences.resetsAddedNotificationsEnabled,
                      previous.preferences.resetsAddedNotificationsEnabled {
                messages.append(("added", "Usage limit resets added", "\(meter.valueText) usage limit resets remaining."))
            }
        }

        // Record the observation before delivery yields to another evaluation.
        amountStateByMeter[meter.id] = state
        if !messages.isEmpty {
            persistHistory()
        }
        for message in messages {
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            await requestDeliverer(UNNotificationRequest(
                identifier: "codexmeter-\(identifierComponent(for: meter.id))-\(message.event)",
                content: content,
                trigger: nil
            ))
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

        let resetWindowChanged: Bool
        if let previousReset = notificationState.resetDate, let resetDate = meter.resetDate {
            resetWindowChanged = abs(resetDate.timeIntervalSince(previousReset)) > Self.resetDateTolerance
        } else {
            resetWindowChanged = false
        }
        if notificationState.threshold != threshold || resetWindowChanged {
            notificationState = ThresholdNotificationState(
                threshold: threshold,
                resetDate: meter.resetDate,
                hasNotified: false
            )
        }
        if notificationState.resetDate == nil {
            notificationState.resetDate = meter.resetDate
        }

        if remainingPercent > threshold.rawValue {
            notificationState.hasNotified = false
            notificationState.resetDate = meter.resetDate ?? notificationState.resetDate
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

        // Reserve the event before delivery yields to another evaluation.
        notificationState.hasNotified = true
        thresholdStateByMeter[meter.id] = notificationState
        persistHistory()
        await requestDeliverer(request)
    }

    private func evaluateResetNotification(meter: UsageMeterViewData, remainingPercent: Int) async {
        var notificationState = resetStateByMeter[meter.id] ?? ResetNotificationState()

        guard remainingPercent >= Self.resetRemainingPercent else {
            notificationState.hasSeenBelowResetLevel = true
            notificationState.hasNotifiedAtResetLevel = false
            resetStateByMeter[meter.id] = notificationState
            return
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

        notificationState.hasNotifiedAtResetLevel = true
        resetStateByMeter[meter.id] = notificationState
        persistHistory()
        await requestDeliverer(request)
    }

    private func bodyText(prefix: String, resetText: String?) -> String {
        if let resetText {
            return "\(prefix) \(resetText)"
        }

        return prefix
    }

    private func identifierComponent(for meterID: UsageMeterID) -> String {
        if meterID.rawValue == "codex.primary" {
            return "codex-primary"
        }

        if meterID.rawValue == "codex.secondary" {
            return "codex-secondary"
        }

        if meterID.rawValue == "credits" {
            return "credits"
        }

        let encodedID = Data(meterID.rawValue.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "dynamic-\(encodedID)"
    }
}
