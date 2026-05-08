import AppKit
import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var loadState: UsageLoadState = .idle
    @Published private(set) var pollingInterval: PollingInterval
    @Published private(set) var statusBarDisplayMode: StatusBarDisplayMode
    @Published private(set) var notificationThreshold: NotificationThreshold?

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
        self.statusBarDisplayMode = preferencesStore.statusBarDisplayMode
        self.notificationThreshold = preferencesStore.notificationThreshold
    }

    deinit {
        refreshTask?.cancel()
        pollingTask?.cancel()
        wakeObserverTask?.cancel()
    }

    var statusBarText: String {
        UsageFormatting.statusBarLabel(snapshot: snapshot, mode: statusBarDisplayMode, state: loadState)
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

    func selectStatusBarDisplayMode(_ mode: StatusBarDisplayMode) {
        statusBarDisplayMode = mode
        preferencesStore.statusBarDisplayMode = mode
    }

    func selectNotificationThreshold(_ threshold: NotificationThreshold?) {
        notificationThreshold = threshold
        preferencesStore.notificationThreshold = threshold

        Task {
            await notificationService.updateThreshold(threshold)

            if threshold != nil {
                _ = await notificationService.requestAuthorizationIfNeeded()
            }
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

        refreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                refreshTask = nil
            }

            do {
                let freshSnapshot = try await usageService.fetchUsageSnapshot()
                snapshot = freshSnapshot
                loadState = .loaded
                await notificationService.evaluateNotifications(for: freshSnapshot, threshold: notificationThreshold)
            } catch let error as UsageServiceError {
                handleRefreshFailure(error)
            } catch {
                handleRefreshFailure(.network(error.localizedDescription))
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
