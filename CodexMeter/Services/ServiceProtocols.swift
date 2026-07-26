import Foundation

struct AuthSession: Sendable {
    let accessToken: String
    let accountID: String?
}

protocol TokenProviding: Sendable {
    func currentSession() async throws -> AuthSession
}

protocol UsageFetching: Sendable {
    func fetchUsageSnapshot() async throws -> UsageSnapshot
}

protocol AppLaunching: Sendable {
    func openUsageDashboard() async -> Bool
    func openCodex() async -> Bool
}

protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async -> Bool
    func evaluateNotifications(
        for snapshot: UsageSnapshot,
        settings: [UsageMeterID: MeterPreferences]
    ) async
}

protocol LoginItemManaging: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ isEnabled: Bool) throws
}
