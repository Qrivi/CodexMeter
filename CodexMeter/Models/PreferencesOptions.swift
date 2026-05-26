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

enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case both = "both"
    case fiveHourRemaining = "five_hour_remaining"
    case weekRemaining = "week_remaining"
    case credits = "credits"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .fiveHourRemaining:
            "5 hour usage limit"
        case .weekRemaining:
            "Weekly usage limit"
        case .both:
            "Both usage limits"
        case .credits:
            "Credits remaining"
        }
    }

    var menuBarTitle: String {
        switch self {
        case .fiveHourRemaining:
            "5 hour"
        case .weekRemaining:
            "Weekly"
        case .both:
            "Limits"
        case .credits:
            "Credits"
        }
    }
}

enum MenuBarColorMode: String, CaseIterable, Identifiable, Sendable {
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
