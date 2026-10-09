import Foundation

enum PollingInterval: Int, CaseIterable, Identifiable, Sendable {
    case seconds30 = 30
    case minute1 = 60
    case minutes2 = 120
    case minutes5 = 300
    case minutes10 = 600
    case minutes15 = 900

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .seconds30:
            "30 seconds"
        case .minute1:
            "1 minute"
        case .minutes2:
            "2 minutes"
        case .minutes5:
            "5 minutes"
        case .minutes10:
            "10 minutes"
        case .minutes15:
            "15 minutes"
        }
    }
}

enum MenuBarDisplayMode: RawRepresentable, Hashable, Identifiable, Sendable {
    case both
    case primaryRemaining
    case secondaryRemaining
    case credits
    case meter(UsageMeterID)

    private static let dynamicMeterPrefix = "meter."

    init?(rawValue: String) {
        switch rawValue {
        case "both":
            self = .both
        case "primary_remaining":
            self = .primaryRemaining
        case "secondary_remaining":
            self = .secondaryRemaining
        case "credits":
            self = .credits
        default:
            guard rawValue.hasPrefix(Self.dynamicMeterPrefix) else {
                return nil
            }

            let meterID = String(rawValue.dropFirst(Self.dynamicMeterPrefix.count))
            guard meterID.isEmpty == false else {
                return nil
            }
            self = .meter(UsageMeterID(rawValue: meterID))
        }
    }

    var rawValue: String {
        switch self {
        case .both:
            "both"
        case .primaryRemaining:
            "primary_remaining"
        case .secondaryRemaining:
            "secondary_remaining"
        case .credits:
            "credits"
        case let .meter(meterID):
            "\(Self.dynamicMeterPrefix)\(meterID.rawValue)"
        }
    }

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .primaryRemaining:
            "Main window"
        case .secondaryRemaining:
            "Secondary window"
        case .both:
            "Main usage limits"
        case .credits:
            "Credits remaining"
        case .meter:
            "Usage meter"
        }
    }
}

enum UsageColorMode: String, CaseIterable, Identifiable, Sendable {
    case monochrome = "monochrome"
    case colorful = "colorful"
    case colorfulWhenLow = "colorful_when_low"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .monochrome:
            "Monochrome"
        case .colorful:
            "Colorful"
        case .colorfulWhenLow:
            "Colorful when low"
        }
    }
}

enum NotificationThreshold: Int, CaseIterable, Identifiable, Sendable {
    case twenty = 20
    case fifteen = 15
    case ten = 10
    case five = 5

    var id: Int { rawValue }

    var title: String {
        "Notify at \(rawValue)%"
    }
}

enum CreditsNotificationThreshold: Int, CaseIterable, Codable, Identifiable, Sendable {
    case twoHundredFifty = 250
    case hundred = 100
    case fifty = 50
    case twentyFive = 25
    case ten = 10

    var id: Int { rawValue }
    var title: String { "Notify at \(rawValue) credits" }
}

struct MeterPreferences: Codable, Equatable, Sendable {
    var isVisible = true
    var notificationThreshold: NotificationThreshold?
    var resetNotificationsEnabled = false
    var creditsNotificationThreshold: CreditsNotificationThreshold?
    var creditsAddedNotificationsEnabled = false
    var resetsUsedNotificationsEnabled = false
    var resetsAddedNotificationsEnabled = false

    nonisolated init(
        isVisible: Bool = true,
        notificationThreshold: NotificationThreshold? = nil,
        resetNotificationsEnabled: Bool = false,
        creditsNotificationThreshold: CreditsNotificationThreshold? = nil,
        creditsAddedNotificationsEnabled: Bool = false,
        resetsUsedNotificationsEnabled: Bool = false,
        resetsAddedNotificationsEnabled: Bool = false
    ) {
        self.isVisible = isVisible
        self.notificationThreshold = notificationThreshold
        self.resetNotificationsEnabled = resetNotificationsEnabled
        self.creditsNotificationThreshold = creditsNotificationThreshold
        self.creditsAddedNotificationsEnabled = creditsAddedNotificationsEnabled
        self.resetsUsedNotificationsEnabled = resetsUsedNotificationsEnabled
        self.resetsAddedNotificationsEnabled = resetsAddedNotificationsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case isVisible, notificationThreshold, resetNotificationsEnabled
        case creditsNotificationThreshold, creditsAddedNotificationsEnabled
        case resetsUsedNotificationsEnabled, resetsAddedNotificationsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        notificationThreshold = try container.decodeIfPresent(NotificationThreshold.self, forKey: .notificationThreshold)
        resetNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .resetNotificationsEnabled) ?? false
        creditsNotificationThreshold = try container.decodeIfPresent(CreditsNotificationThreshold.self, forKey: .creditsNotificationThreshold)
        creditsAddedNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .creditsAddedNotificationsEnabled) ?? false
        resetsUsedNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .resetsUsedNotificationsEnabled) ?? false
        resetsAddedNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .resetsAddedNotificationsEnabled) ?? false
    }
}

extension NotificationThreshold: Codable {}
