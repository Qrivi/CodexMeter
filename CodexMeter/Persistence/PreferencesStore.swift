import Foundation

final class PreferencesStore {
    private enum Default {
        static let pollingInterval: PollingInterval = .minutes5
        static let statusBarDisplayMode: StatusBarDisplayMode = .both
        static let notificationThreshold: NotificationThreshold? = nil
    }

    private enum Key {
        static let pollingInterval = "pollingInterval"
        static let statusBarDisplayMode = "statusBarDisplayMode"
        static let notificationThreshold = "notificationThreshold"
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

    var statusBarDisplayMode: StatusBarDisplayMode {
        get {
            guard let rawValue = userDefaults.string(forKey: Key.statusBarDisplayMode),
                  let displayMode = StatusBarDisplayMode(rawValue: rawValue) else {
                return Default.statusBarDisplayMode
            }

            return displayMode
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Key.statusBarDisplayMode)
        }
    }

    var notificationThreshold: NotificationThreshold? {
        get {
            guard let value = userDefaults.object(forKey: Key.notificationThreshold) as? Int else {
                return Default.notificationThreshold
            }

            return NotificationThreshold(rawValue: value)
        }
        set {
            if let newValue {
                userDefaults.set(newValue.rawValue, forKey: Key.notificationThreshold)
            } else {
                userDefaults.removeObject(forKey: Key.notificationThreshold)
            }
        }
    }
}
