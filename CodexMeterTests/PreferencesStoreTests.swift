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
        #expect(store.limitNotificationThreshold == nil)
        #expect(store.resetNotificationsEnabled == false)
    }

    @Test
    func persistsAndReloadsValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        var store = PreferencesStore(userDefaults: defaults)
        store.pollingInterval = .minutes10
        store.menuBarDisplayMode = .both
        store.menuBarColorMode = .colorfulWhenLow
        store.limitNotificationThreshold = .ten
        store.resetNotificationsEnabled = true

        store = PreferencesStore(userDefaults: defaults)

        #expect(store.pollingInterval == .minutes10)
        #expect(store.menuBarDisplayMode == .both)
        #expect(store.menuBarColorMode == .colorfulWhenLow)
        #expect(store.limitNotificationThreshold == .ten)
        #expect(store.resetNotificationsEnabled)
    }
}
