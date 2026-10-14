import AppKit
import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var isUpdateSessionInProgress = false
    @Published private(set) var updateStatus: AppUpdateStatus = .unavailable
    private(set) var isConfigured = false

    private var controller: SPUStandardUpdaterController?

    init(startingUpdater: Bool = true) {
        super.init()

        // Start updates only after the public signing key has been configured.
        guard startingUpdater,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !ProcessInfo.processInfo.arguments.contains("--disable-updater"),
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: publicKey)?.count == 32 else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        isConfigured = true
        updateStatus = .notChecked

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        controller.updater.publisher(for: \.sessionInProgress)
            .assign(to: &$isUpdateSessionInProgress)
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates, let controller else { return }
        if !controller.updater.sessionInProgress {
            updateStatus = .checking
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func refreshUpdateStatus() {
        guard let updater = controller?.updater, !updater.sessionInProgress else { return }
        updateStatus = .checking
        updater.checkForUpdateInformation()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateStatus = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        switch reason {
        case SPUNoUpdateFoundReason.onLatestVersion.rawValue,
             SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue:
            updateStatus = .current
        default:
            updateStatus = .noUpdateAvailable
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard updateCheck == .updateInformation || updateStatus == .checking else { return }
        if let nsError = error as NSError?,
           nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.noUpdateError.rawValue) {
            return
        }
        if error != nil || updateStatus == .checking {
            updateStatus = .failed
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        // A launch-only override lets release tests use an isolated update feed.
        if let testFeed = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["SUFeedURL"] as? String {
            return testFeed
        }

        #if arch(arm64)
        return "https://qrivi.github.io/CodexMeter/appcast-arm64.xml"
        #else
        return "https://qrivi.github.io/CodexMeter/appcast-x86_64.xml"
        #endif
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Keep Sparkle's windows reachable in the Dock while an update is pending.
        NSApp.setActivationPolicy(.regular)
        NSApp.dockTile.badgeLabel = state.userInitiated ? nil : "1"
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.dockTile.badgeLabel = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
