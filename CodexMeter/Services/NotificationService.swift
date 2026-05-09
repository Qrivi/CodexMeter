import Foundation
@preconcurrency import UserNotifications

actor NotificationService: NotificationScheduling {
    private struct NotificationState: Sendable {
        var resetDate: Date?
        var hasNotified = false
    }

    private let authorizationRequester: @Sendable () async -> Bool
    private let authorizationStatusProvider: @Sendable () async -> UNAuthorizationStatus
    private let requestDeliverer: @Sendable (UNNotificationRequest) async -> Void
    private var currentThreshold: NotificationThreshold?
    private var stateByWindow: [UsageWindowKind: NotificationState] = [:]

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
        if threshold != currentThreshold {
            stateByWindow.removeAll()
        }

        currentThreshold = threshold
    }

    func evaluateNotifications(for snapshot: UsageSnapshot, threshold: NotificationThreshold?) async {
        guard let threshold else {
            return
        }

        let status = await authorizationStatusProvider()
        guard [.authorized, .provisional].contains(status) else {
            return
        }

        await evaluate(section: snapshot.fiveHourSection, threshold: threshold)
        await evaluate(section: snapshot.weeklySection, threshold: threshold)
    }

    private func evaluate(section: UsageSectionViewData, threshold: NotificationThreshold) async {
        guard let remainingPercent = section.remainingPercent else {
            return
        }

        var notificationState = stateByWindow[section.windowKind] ?? NotificationState()

        if notificationState.resetDate != section.resetDate {
            notificationState = NotificationState(resetDate: section.resetDate, hasNotified: false)
        }

        if remainingPercent > threshold.rawValue {
            notificationState.hasNotified = false
            notificationState.resetDate = section.resetDate
            stateByWindow[section.windowKind] = notificationState
            return
        }

        guard notificationState.hasNotified == false else {
            stateByWindow[section.windowKind] = notificationState
            return
        }

        let body: String
        if let resetText = section.resetText {
            body = "\(remainingPercent)% remaining. \(resetText)"
        } else {
            body = "\(remainingPercent)% remaining."
        }

        let content = UNMutableNotificationContent()
        content.title = section.windowKind.notificationTitle
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "codexmeter-\(section.windowKind.rawValue)-\(threshold.rawValue)",
            content: content,
            trigger: nil
        )

        await requestDeliverer(request)
        notificationState.hasNotified = true
        notificationState.resetDate = section.resetDate
        stateByWindow[section.windowKind] = notificationState
    }
}
