import Foundation
@testable import CodexMeter

func makeSnapshot(
    fiveHourRemaining: Int = 64,
    weeklyRemaining: Int = 73,
    fiveHourReset: Date = Date(timeIntervalSince1970: 1_778_070_900),
    weeklyReset: Date = Date(timeIntervalSince1970: 1_778_141_800),
    lastUpdated: Date = Date(timeIntervalSince1970: 1_778_054_820)
) -> UsageSnapshot {
    UsageSnapshot(
        fiveHourSection: UsageSectionViewData(
            title: "5 hour usage limit",
            remainingText: "\(fiveHourRemaining)% remaining",
            resetText: "Resets 2:35 PM (4h 28m)",
            remainingPercent: fiveHourRemaining,
            level: UsageFormatting.level(for: fiveHourRemaining),
            resetDate: fiveHourReset,
            windowKind: .fiveHour
        ),
        weeklySection: UsageSectionViewData(
            title: "Weekly usage limit",
            remainingText: "\(weeklyRemaining)% remaining",
            resetText: "Resets May 6, 2026 10:30 AM (1d 0h)",
            remainingPercent: weeklyRemaining,
            level: UsageFormatting.level(for: weeklyRemaining),
            resetDate: weeklyReset,
            windowKind: .weekly
        ),
        creditsText: "12",
        lastUpdated: lastUpdated,
        warningMessage: nil
    )
}
