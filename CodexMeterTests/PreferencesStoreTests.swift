import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct PreferencesStoreTests {
    @Test
    func providesExpectedDefaults() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = PreferencesStore(userDefaults: defaults)

        #expect(store.pollingInterval == .minutes5)
        #expect(store.menuBarDisplayMode == .both)
        #expect(store.menuBarColorMode == .monochrome)
        #expect(store.meterColorMode == .colorful)
        #expect(store.remainingLabelColorMode == .colorfulWhenLow)
        #expect(store.limitNotificationThreshold == nil)
        #expect(store.resetNotificationsEnabled == false)
        #expect(store.pollOnMenuOpen)
        #expect(store.launchAtLoginEnabled == false)
    }

    @Test
    func persistsAndReloadsValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        var store = PreferencesStore(userDefaults: defaults)
        store.pollingInterval = .minutes10
        store.menuBarDisplayMode = .both
        store.menuBarColorMode = .colorfulWhenLow
        store.meterColorMode = .monochrome
        store.remainingLabelColorMode = .colorful
        store.limitNotificationThreshold = .ten
        store.resetNotificationsEnabled = true
        store.pollOnMenuOpen = false
        store.launchAtLoginEnabled = true

        store = PreferencesStore(userDefaults: defaults)

        #expect(store.pollingInterval == .minutes10)
        #expect(store.menuBarDisplayMode == .both)
        #expect(store.menuBarColorMode == .colorfulWhenLow)
        #expect(store.meterColorMode == .monochrome)
        #expect(store.remainingLabelColorMode == .colorful)
        #expect(store.limitNotificationThreshold == .ten)
        #expect(store.resetNotificationsEnabled)
        #expect(store.pollOnMenuOpen == false)
        #expect(store.launchAtLoginEnabled)
    }
}
