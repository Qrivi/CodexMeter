import AppKit
import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var loadState: UsageLoadState = .idle
    @Published private(set) var pollingInterval: PollingInterval
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode
    @Published private(set) var limitNotificationThreshold: NotificationThreshold?
    @Published private(set) var resetNotificationsEnabled: Bool

    private let usageService: UsageFetching
    private let preferencesStore: PreferencesStore
    private let appLauncher: AppLaunching
    private let notificationService: NotificationScheduling
    private let wakeNotificationCenter: NotificationCenter
    private let now: @Sendable () -> Date

    private var refreshTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var wakeObserverTask: Task<Void, Never>?
    private var didStart = false

    internal private(set) var pollingScheduleVersion = 0

    init(
        usageService: UsageFetching,
        preferencesStore: PreferencesStore,
        appLauncher: AppLaunching,
        notificationService: NotificationScheduling,
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.usageService = usageService
        self.preferencesStore = preferencesStore
        self.appLauncher = appLauncher
        self.notificationService = notificationService
        self.wakeNotificationCenter = wakeNotificationCenter
        self.now = now
        self.pollingInterval = preferencesStore.pollingInterval
        self.menuBarDisplayMode = preferencesStore.menuBarDisplayMode
        self.limitNotificationThreshold = preferencesStore.limitNotificationThreshold
        self.resetNotificationsEnabled = preferencesStore.resetNotificationsEnabled
    }

    deinit {
        refreshTask?.cancel()
        pollingTask?.cancel()
        wakeObserverTask?.cancel()
    }

    var menuBarText: String {
        UsageFormatting.menuBarLabel(snapshot: snapshot, mode: menuBarDisplayMode, state: loadState)
    }

    var menuBarTitle: String {
        menuBarDisplayMode.menuBarTitle
    }

    var isLoadingWithoutSnapshot: Bool {
        snapshot == nil && loadState == .loading
    }

    var currentFailureMessage: String? {
        switch loadState {
        case let .failed(message), let .authFailure(message):
            return message
        default:
            return nil
        }
    }

    var showsAuthGuidance: Bool {
        if case .authFailure = loadState {
            return true
        }

        return snapshot?.authGuidanceMessage != nil
    }

    func start() {
        guard didStart == false else {
            return
        }

        didStart = true
        schedulePolling()
        observeWakeNotifications()
        requestRefresh()
    }

    func menuOpened() {
        requestRefresh()
    }

    func refreshNow() {
        requestRefresh()
    }

    func selectPollingInterval(_ interval: PollingInterval) {
        pollingInterval = interval
        preferencesStore.pollingInterval = interval
        schedulePolling()
    }

    func selectMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        menuBarDisplayMode = mode
        preferencesStore.menuBarDisplayMode = mode
    }

    func selectNotificationThreshold(_ threshold: NotificationThreshold?) {
        limitNotificationThreshold = threshold
        preferencesStore.limitNotificationThreshold = threshold

        Task {
            await notificationService.updateThreshold(threshold)

            if threshold != nil {
                _ = await notificationService.requestAuthorizationIfNeeded()
            }
        }
    }

    func setResetNotificationsEnabled(_ isEnabled: Bool) {
        resetNotificationsEnabled = isEnabled
        preferencesStore.resetNotificationsEnabled = isEnabled

        guard isEnabled else {
            return
        }

        Task {
            _ = await notificationService.requestAuthorizationIfNeeded()
        }
    }

    func openUsageDashboard() {
        Task {
            let opened = await appLauncher.openUsageDashboard()
            guard opened == false else {
                return
            }

            applyNonFatalWarning("Could not open usage dashboard")
        }
    }

    func openCodex() {
        Task {
            let opened = await appLauncher.openCodex()
            guard opened == false else {
                return
            }

            applyNonFatalWarning("Could not open Codex")
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func requestRefresh() {
        guard refreshTask == nil else {
            return
        }

        if snapshot == nil {
            loadState = .loading
        }

        refreshTask = Task.detached { [weak self, usageService, notificationService] in
            do {
                let freshSnapshot = try await usageService.fetchUsageSnapshot()

                let notificationSettings: (NotificationThreshold?, Bool) = await MainActor.run { [weak self] in
                    guard let self, Task.isCancelled == false else {
                        return (nil, false)
                    }

                    snapshot = freshSnapshot
                    loadState = .loaded
                    return (limitNotificationThreshold, resetNotificationsEnabled)
                }

                await notificationService.evaluateNotifications(
                    for: freshSnapshot,
                    threshold: notificationSettings.0,
                    resetNotificationsEnabled: notificationSettings.1
                )
            } catch let error as UsageServiceError {
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(error)
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.handleRefreshFailure(.network(message))
                }
            }

            await MainActor.run { [weak self] in
                self?.refreshTask = nil
            }
        }
    }

    private func handleRefreshFailure(_ error: UsageServiceError) {
        switch error {
        case .auth, .unauthorized:
            if let snapshot {
                self.snapshot = snapshot.withMessages(
                    warningMessage: "Update failed",
                    authGuidanceMessage: error.userFacingMessage
                )
                loadState = .loaded
            } else {
                loadState = .authFailure(message: error.userFacingMessage)
            }

        case .network, .invalidResponse, .decoding:
            if let snapshot {
                self.snapshot = snapshot.withMessages(warningMessage: "Update failed", authGuidanceMessage: nil)
                loadState = .loaded
            } else {
                loadState = .failed(message: error.userFacingMessage)
            }
        }
    }

    private func applyNonFatalWarning(_ message: String) {
        if let snapshot {
            self.snapshot = snapshot.withMessages(
                warningMessage: message,
                authGuidanceMessage: snapshot.authGuidanceMessage
            )
        } else {
            loadState = .failed(message: message)
        }
    }

    private func schedulePolling() {
        pollingTask?.cancel()
        pollingScheduleVersion += 1
        let interval = UInt64(pollingInterval.rawValue) * 1_000_000_000

        pollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: interval)

                if Task.isCancelled {
                    break
                }

                await MainActor.run {
                    self?.refreshNow()
                }
            }
        }
    }

    private func observeWakeNotifications() {
        wakeObserverTask?.cancel()

        wakeObserverTask = Task { [weak self, wakeNotificationCenter] in
            for await _ in wakeNotificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                if Task.isCancelled {
                    break
                }

                await MainActor.run {
                    self?.refreshNow()
                }
            }
        }
    }
}
