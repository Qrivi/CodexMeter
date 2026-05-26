import Foundation
import UserNotifications
@testable import CodexMeter

struct MockTokenProvider: TokenProviding {
    let result: Result<AuthSession, Error>

    func currentSession() async throws -> AuthSession {
        try result.get()
    }
}

actor MockUsageFetcher: UsageFetching {
    private var results: [Result<UsageSnapshot, Error>]

    init(results: [Result<UsageSnapshot, Error>]) {
        self.results = results
    }

    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        let result = results.removeFirst()
        return try result.get()
    }
}

actor BlockingUsageFetcher: UsageFetching {
    private let tracker: RefreshTracker
    private let snapshot: UsageSnapshot

    init(tracker: RefreshTracker, snapshot: UsageSnapshot) {
        self.tracker = tracker
        self.snapshot = snapshot
    }

    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        await tracker.recordCallAndWaitUntilResumed()
        return snapshot
    }
}

actor RefreshTracker {
    private var callCountValue = 0
    private var callContinuation: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    var callCount: Int {
        get { callCountValue }
    }

    func recordCallAndWaitUntilResumed() async {
        callCountValue += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            callContinuation?.resume()
            callContinuation = nil
        }
    }

    func waitUntilCalled() async {
        if callCountValue > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            callContinuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

actor NotificationTracker {
    private(set) var identifiers: [String] = []
    private(set) var bodies: [String] = []
    private(set) var authorizationRequestCount = 0

    func record(request: UNNotificationRequest) {
        identifiers.append(request.identifier)
        bodies.append(request.content.body)
    }

    func markAuthorizationRequested() {
        authorizationRequestCount += 1
    }
}

final class LauncherRecorder: @unchecked Sendable {
    private(set) var urls: [URL] = []
    private(set) var steps: [String] = []

    func recordURL(_ url: URL) {
        urls.append(url)
    }

    func recordStep(_ step: String) {
        steps.append(step)
    }
}

final class MockNotificationService: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var authorizationRequestCountValue = 0

    var authorizationRequestCount: Int {
        lock.withLock {
            authorizationRequestCountValue
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        lock.withLock {
            authorizationRequestCountValue += 1
        }
        return true
    }

    func updateThreshold(_ threshold: NotificationThreshold?) async {}
    func evaluateNotifications(
        for snapshot: UsageSnapshot,
        threshold: NotificationThreshold?,
        resetNotificationsEnabled: Bool
    ) async {}
}

struct MockAppLauncher: AppLaunching {
    func openUsageDashboard() async -> Bool { true }
    func openCodex() async -> Bool { true }
}

final class MockLoginItemService: LoginItemManaging, @unchecked Sendable {
    enum MockError: Error {
        case failed
    }

    private let lock = NSLock()
    private var isEnabledValue: Bool
    private var shouldFailValue: Bool
    private var setValues: [Bool] = []

    init(isEnabled: Bool = false, shouldFail: Bool = false) {
        self.isEnabledValue = isEnabled
        self.shouldFailValue = shouldFail
    }

    var requestedValues: [Bool] {
        lock.withLock {
            setValues
        }
    }

    func isEnabled() -> Bool {
        lock.withLock {
            isEnabledValue
        }
    }

    func setEnabled(_ isEnabled: Bool) throws {
        try lock.withLock {
            setValues.append(isEnabled)

            if shouldFailValue {
                throw MockError.failed
            }

            isEnabledValue = isEnabled
        }
    }
}

func makeNotificationService(tracker: NotificationTracker) -> NotificationService {
    NotificationService(
        authorizationRequester: { true },
        authorizationStatusProvider: { .authorized },
        requestDeliverer: { request in
            await tracker.record(request: request)
        }
    )
}

@MainActor
func makeViewModel(
    service: UsageFetching,
    preferencesStore: PreferencesStore? = nil,
    notificationService: NotificationScheduling = MockNotificationService(),
    loginItemService: LoginItemManaging = MockLoginItemService()
) -> UsageViewModel {
    let store = preferencesStore ?? PreferencesStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    return UsageViewModel(
        usageService: service,
        preferencesStore: store,
        appLauncher: MockAppLauncher(),
        notificationService: notificationService,
        loginItemService: loginItemService,
        wakeNotificationCenter: NotificationCenter()
    )
}
