import Foundation

enum UsageWindowKind: String, Sendable {
    case fiveHour
    case weekly

    nonisolated var sectionTitle: String {
        switch self {
        case .fiveHour:
            "5 hour usage limit"
        case .weekly:
            "Weekly usage limit"
        }
    }

    nonisolated var limitNotificationTitle: String {
        switch self {
        case .fiveHour:
            "Codex 5 hour usage limit is low"
        case .weekly:
            "Codex weekly usage limit is low"
        }
    }

    nonisolated var resetNotificationTitle: String {
        switch self {
        case .fiveHour:
            "Codex 5 hour usage limit reset"
        case .weekly:
            "Codex weekly usage limit reset"
        }
    }
}

struct UsageSectionViewData: Equatable, Sendable {
    let title: String
    let remainingText: String
    let resetText: String?
    let remainingPercent: Int?
    let level: UsageLevel
    let resetDate: Date?
    let windowKind: UsageWindowKind

    static func unavailable(kind: UsageWindowKind) -> UsageSectionViewData {
        UsageSectionViewData(
            title: kind.sectionTitle,
            remainingText: "Unavailable",
            resetText: nil,
            remainingPercent: nil,
            level: .neutral,
            resetDate: nil,
            windowKind: kind
        )
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let fiveHourSection: UsageSectionViewData
    let weeklySection: UsageSectionViewData
    let creditsText: String
    let lastUpdated: Date
    let warningMessage: String?

    func withMessages(warningMessage: String? = nil) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourSection: fiveHourSection,
            weeklySection: weeklySection,
            creditsText: creditsText,
            lastUpdated: lastUpdated,
            warningMessage: warningMessage
        )
    }
}
