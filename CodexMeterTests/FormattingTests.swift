import AppKit
import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct FormattingTests {
    @Test
    func mapsUsedPercentToRemainingPercent() {
        #expect(UsageFormatting.remainingPercent(from: 36) == 64)
        #expect(UsageFormatting.remainingPercent(from: 100) == 0)
    }

    @Test
    func buildsResetTextFromResetAt() {
        let now = Date(timeIntervalSince1970: 1_778_054_820)
        let resetDate = Date(timeIntervalSince1970: 1_778_070_900)

        let text = UsageFormatting.resetText(
            resetDate: resetDate,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "Resets 2:35 PM (4h 28m)")
    }

    @Test
    func buildsResetTextWithDateWhenResetIsAnotherDay() {
        let now = Date(timeIntervalSince1970: 1_778_054_820)
        let resetDate = Date(timeIntervalSince1970: 1_778_141_800)

        let text = UsageFormatting.resetText(
            resetDate: resetDate,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "Resets May 6, 2026 10:30 AM (1d 0h)")
    }

    @Test
    func buildsLastUpdatedTextWithTimeWhenUpdatedToday() {
        let now = Date(timeIntervalSince1970: 1_778_054_820)
        let lastUpdated = Date(timeIntervalSince1970: 1_778_054_340)

        let text = UsageFormatting.lastUpdatedText(
            from: lastUpdated,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "9:59 AM")
    }

    @Test
    func buildsLastUpdatedTextWithDateWhenUpdatedAnotherDay() {
        let now = Date(timeIntervalSince1970: 1_778_141_800)
        let lastUpdated = Date(timeIntervalSince1970: 1_778_054_820)

        let text = UsageFormatting.lastUpdatedText(
            from: lastUpdated,
            now: now,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(text == "May 5, 2026 10:07 AM")
    }

    @Test
    func fallsBackToResetAfterSeconds() {
        let now = Date(timeIntervalSince1970: 1_778_054_820)
        let window = UsageWindow(
            usedPercent: 36,
            limitWindowSeconds: 18_000,
            resetAfterSeconds: 7_200,
            resetAt: nil
        )

        let resetDate = UsageFormatting.resetDate(for: window, now: now)

        #expect(resetDate == now.addingTimeInterval(7_200))
    }

    @Test
    func rendersCreditsAsUnlimitedOrRawBalance() {
        let unlimitedCredits = CreditsInfo(unlimited: true, balance: .int(0), hasCredits: true)
        let finiteCredits = CreditsInfo(unlimited: false, balance: .string("42.5"), hasCredits: true)

        #expect(UsageFormatting.creditsText(from: unlimitedCredits) == "Unlimited")
        #expect(UsageFormatting.creditsText(from: finiteCredits) == "42.5")
    }

    @Test
    func buildsMenuBarSegmentsWithColorMode() {
        let snapshot = makeSnapshot(fiveHourRemaining: 64, weeklyRemaining: 18)

        let colorfulSegments = UsageFormatting.menuBarLabelSegments(
            snapshot: snapshot,
            mode: .both,
            colorMode: .colorful,
            state: .loaded
        )

        #expect(colorfulSegments == [
            MenuBarLabelSegment(text: "64%", tone: .good),
            MenuBarLabelSegment(text: "/", tone: .neutral),
            MenuBarLabelSegment(text: "18%", tone: .critical)
        ])
    }

    @Test
    func onlyColorsMenuBarSegmentWhenLowAtTwentyPercent() {
        let snapshot = makeSnapshot(fiveHourRemaining: 21, weeklyRemaining: 20)

        let segments = UsageFormatting.menuBarLabelSegments(
            snapshot: snapshot,
            mode: .both,
            colorMode: .colorfulWhenLow,
            state: .loaded
        )

        #expect(segments == [
            MenuBarLabelSegment(text: "21%", tone: .neutral),
            MenuBarLabelSegment(text: "/", tone: .neutral),
            MenuBarLabelSegment(text: "20%", tone: .critical)
        ])
    }

    @Test
    func keepsCreditsAndFallbackMenuBarSegmentsNeutral() {
        let snapshot = makeSnapshot()

        let creditsSegments = UsageFormatting.menuBarLabelSegments(
            snapshot: snapshot,
            mode: .credits,
            colorMode: .colorful,
            state: .loaded
        )
        let fallbackSegments = UsageFormatting.menuBarLabelSegments(
            snapshot: nil,
            mode: .fiveHourRemaining,
            colorMode: .colorful,
            state: .loading
        )

        #expect(creditsSegments == [MenuBarLabelSegment(text: "12 cr", tone: .neutral)])
        #expect(fallbackSegments == [MenuBarLabelSegment(text: "…", tone: .neutral)])
    }

    @Test
    func usesCompactErrorMenuBarSegmentsWhenSnapshotHasFailureMessage() {
        let warningSnapshot = makeSnapshot().withMessages(warningMessage: "Offline")

        #expect(UsageFormatting.menuBarLabelSegments(
            snapshot: warningSnapshot,
            mode: .both,
            colorMode: .colorful,
            state: .loaded
        ) == [MenuBarLabelSegment(text: "Error", tone: .critical)])
        #expect(UsageFormatting.menuBarLabel(snapshot: nil, mode: .both, state: .failed(message: "Offline")) == "Error")
    }

    @Test
    func menuBarLabelNeutralColorFollowsMenuBarAppearance() {
        #expect(MenuBarLabelColors.color(for: .neutral, isMenuBarDark: true) == .white)
        #expect(MenuBarLabelColors.color(for: .neutral, isMenuBarDark: false) == .black)
        #expect(MenuBarLabelColors.color(for: .critical, isMenuBarDark: true) == UsageStatusPalette.criticalColor)
        #expect(MenuBarLabelColors.color(for: .critical, isMenuBarDark: false) == UsageStatusPalette.criticalColor)
    }
}
