import AppKit
import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var loadState: UsageLoadState = .idle
    @Published private(set) var pollingInterval: PollingInterval
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode
    @Published private(set) var menuBarColorMode: UsageColorMode
    @Published private(set) var meterColorMode: UsageColorMode
    @Published private(set) var remainingLabelColorMode: UsageColorMode
    @Published private(set) var meterPreferences: [UsageMeterID: MeterPreferences]
    @Published private(set) var pollOnMenuOpen: Bool
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var settingsErrorMessage: String?

    private let usageService: UsageFetching
    private let preferencesStore: PreferencesStore
    private let appLauncher: AppLaunching
    private let notificationService: NotificationScheduling
    private let loginItemService: LoginItemManaging
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
        loginItemService: LoginItemManaging,
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.usageService = usageService
        self.preferencesStore = preferencesStore
        self.appLauncher = appLauncher
        self.notificationService = notificationService
        self.loginItemService = loginItemService
        self.wakeNotificationCenter = wakeNotificationCenter
        self.now = now
        self.pollingInterval = preferencesStore.pollingInterval
        self.menuBarDisplayMode = preferencesStore.menuBarDisplayMode
        self.menuBarColorMode = preferencesStore.menuBarColorMode
        self.meterColorMode = preferencesStore.meterColorMode
        self.remainingLabelColorMode = preferencesStore.remainingLabelColorMode
        self.meterPreferences = preferencesStore.meterPreferences
        self.pollOnMenuOpen = preferencesStore.pollOnMenuOpen
        self.launchAtLoginEnabled = loginItemService.isEnabled()
        preferencesStore.launchAtLoginEnabled = launchAtLoginEnabled
    }

    deinit {
        refreshTask?.cancel()
        pollingTask?.cancel()
        wakeObserverTask?.cancel()
    }

    var menuBarText: String {
        UsageFormatting.menuBarLabel(snapshot: snapshot, mode: menuBarDisplayMode, state: loadState)
    }

    var menuBarTextSegments: [MenuBarLabelSegment] {
        UsageFormatting.menuBarLabelSegments(
            snapshot: snapshot,
            mode: menuBarDisplayMode,
            colorMode: menuBarColorMode,
            state: loadState
        )
    }

    var menuBarTitle: String {
        UsageFormatting.menuBarTitle(snapshot: snapshot, mode: menuBarDisplayMode)
    }

    var menuBarDisplayOptions: [MenuBarDisplayMode] {
        var options: [MenuBarDisplayMode] = [
            .both,
            .primaryRemaining,
            .secondaryRemaining
        ]
        if let snapshot {
            options.append(contentsOf: snapshot.additionalRateLimitMeters.map {
                .meter($0.id)
            })
        } else if case .meter = menuBarDisplayMode {
            // Keep a persisted dynamic selection valid while the first refresh is loading.
            options.append(menuBarDisplayMode)
        }
        options.append(.credits)
        return options
    }

    var menuBarDisplayDividerOptions: Set<MenuBarDisplayMode> {
        var dividers: Set<MenuBarDisplayMode> = [.credits]
        if let firstAdditionalMeter = menuBarDisplayOptions.first(where: {
            if case .meter = $0 {
                return true
            }
            return false
        }) {
            dividers.insert(firstAdditionalMeter)
        }
        return dividers
    }

    func menuBarDisplayTitle(for mode: MenuBarDisplayMode) -> String {
        switch mode {
        case .primaryRemaining:
            snapshot?.meter(id: .primary)?.title ?? mode.menuTitle
        case .secondaryRemaining:
            snapshot?.meter(id: .secondary)?.title ?? mode.menuTitle
        case .both, .credits:
            mode.menuTitle
        case let .meter(meterID):
            snapshot?.meter(id: meterID)?.title ?? mode.menuTitle
        }
    }

    func isMenuBarDisplayModeEnabled(_ mode: MenuBarDisplayMode) -> Bool {
        guard let snapshot else {
            return true
        }

        return isMenuBarDisplayModeEnabled(mode, in: snapshot)
    }

    var isLoadingWithoutSnapshot: Bool {
        snapshot == nil && loadState == .loading
    }

    var currentFailureMessage: String? {
        switch loadState {
        case let .failed(message):
            return message
        default:
            return nil
        }
    }

    func canRefreshNow(at date: Date = Date()) -> Bool {
        guard let snapshot else {
            return true
        }

        return date.timeIntervalSince(snapshot.lastUpdated) >= 60
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
        guard pollOnMenuOpen else {
            return
        }

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
        guard isMenuBarDisplayModeEnabled(mode) else {
            return
        }

        menuBarDisplayMode = mode
        preferencesStore.menuBarDisplayMode = mode
    }

    func selectMenuBarColorMode(_ mode: UsageColorMode) {
        menuBarColorMode = mode
        preferencesStore.menuBarColorMode = mode
    }

    func selectMeterColorMode(_ mode: UsageColorMode) {
        meterColorMode = mode
        preferencesStore.meterColorMode = mode
    }

    func selectRemainingLabelColorMode(_ mode: UsageColorMode) {
        remainingLabelColorMode = mode
        preferencesStore.remainingLabelColorMode = mode
    }

    func setPollOnMenuOpen(_ isEnabled: Bool) {
        pollOnMenuOpen = isEnabled
        preferencesStore.pollOnMenuOpen = isEnabled
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        let previousValue = launchAtLoginEnabled
        launchAtLoginEnabled = isEnabled
        settingsErrorMessage = nil

        do {
            try loginItemService.setEnabled(isEnabled)
            launchAtLoginEnabled = loginItemService.isEnabled()
            preferencesStore.launchAtLoginEnabled = launchAtLoginEnabled
        } catch {
            launchAtLoginEnabled = previousValue
            preferencesStore.launchAtLoginEnabled = previousValue
            settingsErrorMessage = "Could not update launch at login."
        }
    }

    func clearSettingsErrorMessage() {
        settingsErrorMessage = nil
    }

    func preferences(for meterID: UsageMeterID) -> MeterPreferences {
        meterPreferences[meterID] ?? MeterPreferences()
    }

    func visibleMeters(in snapshot: UsageSnapshot) -> [UsageMeterViewData] {
        snapshot.meters.filter { meter in
            meter.isAvailable && preferences(for: meter.id).isVisible
        }
    }

    func meterEmptyStateMessage(in snapshot: UsageSnapshot) -> String {
        let hasEnabledMeter = snapshot.meters.contains { meter in
            preferences(for: meter.id).isVisible
        }

        return hasEnabledMeter
            ? "No usage meters are currently available."
            : "No meters are enabled. You can enable meters in Settings."
    }

    func setMeterVisible(_ isVisible: Bool, meterID: UsageMeterID) {
        updatePreferences(for: meterID) { preferences in
            preferences.isVisible = isVisible
        }
    }

    func selectNotificationThreshold(_ threshold: NotificationThreshold?, meterID: UsageMeterID) {
        updatePreferences(for: meterID) { preferences in
            preferences.notificationThreshold = threshold
        }

        Task {
            if threshold != nil {
                _ = await notificationService.requestAuthorizationIfNeeded()
            }
        }
    }

    func setResetNotificationsEnabled(_ isEnabled: Bool, meterID: UsageMeterID) {
        updatePreferences(for: meterID) { preferences in
            preferences.resetNotificationsEnabled = isEnabled
        }

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

                let notificationSettings: [UsageMeterID: MeterPreferences] = await MainActor.run { [weak self] in
                    guard let self, Task.isCancelled == false else {
                        return [:]
                    }

                    snapshot = freshSnapshot
                    loadState = .loaded
                    reconcileMenuBarDisplayMode(with: freshSnapshot)
                    return Dictionary(uniqueKeysWithValues: freshSnapshot.meters.map { meter in
                        (meter.id, self.preferences(for: meter.id))
                    })
                }

                await notificationService.evaluateNotifications(
                    for: freshSnapshot,
                    settings: notificationSettings
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
                self.snapshot = snapshot.withMessages(warningMessage: error.userFacingMessage)
                loadState = .loaded
            } else {
                loadState = .failed(message: error.userFacingMessage)
            }

        case .network, .invalidResponse, .decoding:
            if let snapshot {
                self.snapshot = snapshot.withMessages(warningMessage: error.userFacingMessage)
                loadState = .loaded
            } else {
                loadState = .failed(message: error.userFacingMessage)
            }
        }
    }

    private func applyNonFatalWarning(_ message: String) {
        if let snapshot {
            self.snapshot = snapshot.withMessages(warningMessage: message)
        } else {
            loadState = .failed(message: message)
        }
    }

    private func updatePreferences(
        for meterID: UsageMeterID,
        change: (inout MeterPreferences) -> Void
    ) {
        var preferences = preferences(for: meterID)
        change(&preferences)
        meterPreferences[meterID] = preferences
        preferencesStore.meterPreferences = meterPreferences
    }

    private func reconcileMenuBarDisplayMode(with snapshot: UsageSnapshot) {
        guard isMenuBarDisplayModeEnabled(menuBarDisplayMode, in: snapshot) == false else {
            return
        }

        let fallbackMode: MenuBarDisplayMode
        if snapshot.mainRateLimitMeters.contains(where: \.isAvailable) {
            fallbackMode = .both
        } else if let additionalMeter = snapshot.additionalRateLimitMeters.first(where: \.isAvailable) {
            fallbackMode = .meter(additionalMeter.id)
        } else if snapshot.creditsMeter?.isAvailable == true {
            fallbackMode = .credits
        } else {
            fallbackMode = .both
        }

        menuBarDisplayMode = fallbackMode
        preferencesStore.menuBarDisplayMode = fallbackMode
    }

    private func isMenuBarDisplayModeEnabled(
        _ mode: MenuBarDisplayMode,
        in snapshot: UsageSnapshot
    ) -> Bool {
        switch mode {
        case .both:
            snapshot.mainRateLimitMeters.contains(where: \.isAvailable)
        case .primaryRemaining:
            snapshot.meter(id: .primary)?.isAvailable == true
        case .secondaryRemaining:
            snapshot.meter(id: .secondary)?.isAvailable == true
        case .credits:
            snapshot.creditsMeter?.isAvailable == true
        case let .meter(meterID):
            snapshot.meter(id: meterID)?.isAvailable == true
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

#if DEBUG
extension UsageViewModel {
    func applyPreviewSnapshot(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        loadState = .loaded
    }

    func applyPreviewFailure(_ message: String) {
        snapshot = nil
        loadState = .failed(message: message)
    }
}
#endif
