import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct PreferencesStoreTests {
    @Test
    func preservesExistingPreferencesWhenNewNotificationFieldsAreMissing() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        defaults.set(Data(#"{"codex.primary":{"isVisible":false,"notificationThreshold":10,"resetNotificationsEnabled":true},"credits":{"isVisible":true,"resetNotificationsEnabled":false}}"#.utf8), forKey: "meterPreferences.v2")
        let preferences = PreferencesStore(userDefaults: defaults).meterPreferences
        #expect(preferences[.primary] == MeterPreferences(isVisible: false, notificationThreshold: .ten, resetNotificationsEnabled: true))
        #expect(preferences[.credits] == MeterPreferences())
    }

    @Test
    func persistsCreditAndResetNotifications() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let preferences: [UsageMeterID: MeterPreferences] = [
            .credits: MeterPreferences(creditsNotificationThreshold: .fifty, creditsAddedNotificationsEnabled: true),
            .usageLimitResets: MeterPreferences(resetsUsedNotificationsEnabled: true, resetsAddedNotificationsEnabled: true)
        ]
        PreferencesStore(userDefaults: defaults).meterPreferences = preferences
        #expect(PreferencesStore(userDefaults: defaults).meterPreferences == preferences)
    }

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
        #expect(store.meterPreferences.isEmpty)
        #expect(store.pollOnMenuOpen)
        #expect(store.launchAtLoginEnabled == false)
    }

    @Test
    func persistsAndReloadsValues() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let sparkMeterID = UsageMeterID.additional(
            feature: "codex_bengalfox",
            slot: .secondary
        )

        var store = PreferencesStore(userDefaults: defaults)
        store.pollingInterval = .minutes10
        store.menuBarDisplayMode = .meter(sparkMeterID)
        store.menuBarColorMode = .colorfulWhenLow
        store.meterColorMode = .monochrome
        store.remainingLabelColorMode = .colorful
        store.meterPreferences = [
            .primary: MeterPreferences(
                isVisible: false,
                notificationThreshold: .ten,
                resetNotificationsEnabled: true
            )
        ]
        store.pollOnMenuOpen = false
        store.launchAtLoginEnabled = true

        store = PreferencesStore(userDefaults: defaults)

        #expect(store.pollingInterval == .minutes10)
        #expect(store.menuBarDisplayMode == .meter(sparkMeterID))
        #expect(store.menuBarColorMode == .colorfulWhenLow)
        #expect(store.meterColorMode == .monochrome)
        #expect(store.remainingLabelColorMode == .colorful)
        #expect(store.meterPreferences[.primary] == MeterPreferences(
            isVisible: false,
            notificationThreshold: .ten,
            resetNotificationsEnabled: true
        ))
        #expect(store.pollOnMenuOpen == false)
        #expect(store.launchAtLoginEnabled)
    }
}
