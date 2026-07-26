import Foundation

final class PreferencesStore {
    private enum Default {
        static let pollingInterval: PollingInterval = .minutes5
        static let menuBarDisplayMode: MenuBarDisplayMode = .both
        static let menuBarColorMode: UsageColorMode = .monochrome
        static let meterColorMode: UsageColorMode = .colorful
        static let remainingLabelColorMode: UsageColorMode = .colorfulWhenLow
        static let pollOnMenuOpen = true
        static let launchAtLoginEnabled = false
    }

    private enum Key {
        static let pollingInterval = "pollingInterval"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let legacyMenuBarDisplayMode = "statusBarDisplayMode"
        static let menuBarColorMode = "menuBarColorMode"
        static let meterColorMode = "meterColorMode"
        static let remainingLabelColorMode = "remainingLabelColorMode"
        static let meterPreferences = "meterPreferences.v2"
        static let pollOnMenuOpen = "pollOnMenuOpen"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var pollingInterval: PollingInterval {
        get {
            guard let interval = PollingInterval(rawValue: userDefaults.integer(forKey: Key.pollingInterval)),
                  userDefaults.object(forKey: Key.pollingInterval) != nil else {
                return Default.pollingInterval
            }

            return interval
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.pollingInterval)
        }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get {
            guard let rawValue = userDefaults.string(forKey: Key.menuBarDisplayMode)
                ?? userDefaults.string(forKey: Key.legacyMenuBarDisplayMode),
                  let displayMode = MenuBarDisplayMode(rawValue: rawValue) else {
                return Default.menuBarDisplayMode
            }

            return displayMode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.menuBarDisplayMode)
        }
    }

    var menuBarColorMode: UsageColorMode {
        get {
            guard let rawValue = userDefaults.string(forKey: Key.menuBarColorMode),
                  let colorMode = UsageColorMode(rawValue: rawValue) else {
                return Default.menuBarColorMode
            }

            return colorMode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.menuBarColorMode)
        }
    }

    var meterColorMode: UsageColorMode {
        get {
            usageColorMode(forKey: Key.meterColorMode, defaultValue: Default.meterColorMode)
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.meterColorMode)
        }
    }

    var remainingLabelColorMode: UsageColorMode {
        get {
            usageColorMode(forKey: Key.remainingLabelColorMode, defaultValue: Default.remainingLabelColorMode)
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.remainingLabelColorMode)
        }
    }

    var meterPreferences: [UsageMeterID: MeterPreferences] {
        get {
            guard let data = userDefaults.data(forKey: Key.meterPreferences),
                  let stored = try? JSONDecoder().decode([String: MeterPreferences].self, from: data) else {
                return [:]
            }

            return Dictionary(uniqueKeysWithValues: stored.map { (UsageMeterID(rawValue: $0.key), $0.value) })
        }
        set {
            let stored = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            guard let data = try? JSONEncoder().encode(stored) else {
                return
            }

            userDefaults.set(data, forKey: Key.meterPreferences)
        }
    }

    var pollOnMenuOpen: Bool {
        get {
            guard userDefaults.object(forKey: Key.pollOnMenuOpen) != nil else {
                return Default.pollOnMenuOpen
            }

            return userDefaults.bool(forKey: Key.pollOnMenuOpen)
        }
        set {
            userDefaults.set(newValue, forKey: Key.pollOnMenuOpen)
        }
    }

    var launchAtLoginEnabled: Bool {
        get {
            guard userDefaults.object(forKey: Key.launchAtLoginEnabled) != nil else {
                return Default.launchAtLoginEnabled
            }

            return userDefaults.bool(forKey: Key.launchAtLoginEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Key.launchAtLoginEnabled)
        }
    }

    private func usageColorMode(forKey key: String, defaultValue: UsageColorMode) -> UsageColorMode {
        guard let rawValue = userDefaults.string(forKey: key),
              let colorMode = UsageColorMode(rawValue: rawValue) else {
            return defaultValue
        }

        return colorMode
    }
}
