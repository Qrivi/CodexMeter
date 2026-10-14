import Foundation
import Sparkle
import Testing
@testable import CodexMeter

@MainActor
struct AppUpdaterTests {
    private func sparkleUpdater() -> SPUUpdater {
        SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
    }

    @Test
    func disabledUpdaterDoesNotClaimTheAppIsCurrent() {
        let updater = AppUpdater(startingUpdater: false)
        updater.refreshUpdateStatus()
        #expect(updater.updateStatus == .unavailable)
    }

    @Test
    func foundUpdateSurvivesSuccessfulProbeCompletion() throws {
        let item = try #require(SUAppcastItem(dictionary: [
            "sparkle:version": "200",
            "sparkle:shortVersionString": "1.3.1",
            "enclosure": ["url": "https://example.invalid/CodexMeter.dmg"]
        ]))
        let updater = AppUpdater(startingUpdater: false)
        let sparkle = sparkleUpdater()
        updater.updater(sparkle, didFindValidUpdate: item)
        updater.updater(sparkle, didFinishUpdateCycleFor: .updateInformation, error: nil)
        #expect(updater.updateStatus == .available(version: "1.3.1"))
    }

    @Test
    func noUpdateResultIsNotOverwrittenByCycleCompletion() {
        let updater = AppUpdater(startingUpdater: false)
        let sparkle = sparkleUpdater()
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
                            userInfo: [SPUNoUpdateFoundReasonKey: SPUNoUpdateFoundReason.onLatestVersion.rawValue])
        updater.updaterDidNotFindUpdate(sparkle, error: error)
        updater.updater(sparkle, didFinishUpdateCycleFor: .updateInformation, error: error)
        #expect(updater.updateStatus == .current)
    }

    @Test
    func incompatibleUpdateDoesNotClaimTheAppIsOnTheLatestRelease() {
        let updater = AppUpdater(startingUpdater: false)
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue),
                            userInfo: [SPUNoUpdateFoundReasonKey: SPUNoUpdateFoundReason.systemIsTooOld.rawValue])
        updater.updaterDidNotFindUpdate(sparkleUpdater(), error: error)
        #expect(updater.updateStatus == .noUpdateAvailable)
    }

    @Test
    func failedInformationCheckDoesNotClaimTheAppIsCurrent() {
        let updater = AppUpdater(startingUpdater: false)
        updater.updater(sparkleUpdater(), didFinishUpdateCycleFor: .updateInformation,
                        error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        #expect(updater.updateStatus == .failed)
    }
}
