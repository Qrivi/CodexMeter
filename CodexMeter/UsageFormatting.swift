import Foundation

enum UsageFormatting {
    static func snapshot(from response: UsageResponse, now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourSection: sectionData(for: response.rateLimit?.primaryWindow, kind: .fiveHour, now: now),
            weeklySection: sectionData(for: response.rateLimit?.secondaryWindow, kind: .weekly, now: now),
            creditsText: creditsText(from: response.credits),
            lastUpdated: now,
            warningMessage: nil,
            authGuidanceMessage: nil
        )
    }

    static func sectionData(
        for window: UsageWindow?,
        kind: UsageWindowKind,
        now: Date = Date()
    ) -> UsageSectionViewData {
        guard let window else {
            return .unavailable(kind: kind)
        }

        guard let remainingPercent = remainingPercent(from: window.usedPercent) else {
            return .unavailable(kind: kind)
        }

        let resetDate = resetDate(for: window, now: now)

        return UsageSectionViewData(
            title: kind.sectionTitle,
            remainingText: "\(remainingPercent)% remaining",
            progressValue: progressValue(from: window.usedPercent),
            resetText: resetText(resetDate: resetDate, now: now),
            remainingPercent: remainingPercent,
            level: level(for: remainingPercent),
            resetDate: resetDate,
            windowKind: kind
        )
    }

    static func remainingPercent(from usedPercent: Double?) -> Int? {
        guard let usedPercent else {
            return nil
        }

        let used = Int(usedPercent.rounded())
        return max(0, min(100, 100 - used))
    }

    static func progressValue(from usedPercent: Double?) -> Double? {
        guard let usedPercent else {
            return nil
        }

        return min(max(usedPercent / 100.0, 0), 1)
    }

    static func resetDate(for window: UsageWindow, now: Date = Date()) -> Date? {
        if let resetAt = window.resetAt {
            return Date(timeIntervalSince1970: resetAt)
        }

        if let resetAfterSeconds = window.resetAfterSeconds {
            return now.addingTimeInterval(TimeInterval(resetAfterSeconds))
        }

        return nil
    }

    static func resetText(
        resetDate: Date?,
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let resetDate else {
            return nil
        }

        let relative = relativeResetText(resetDate: resetDate, now: now)
        let absolute = absoluteResetText(resetDate: resetDate, locale: locale, timeZone: timeZone)
        return "\(relative) · \(absolute)"
    }

    static func relativeResetText(resetDate: Date, now: Date = Date()) -> String {
        let seconds = max(Int(resetDate.timeIntervalSince(now)), 0)

        if seconds < 60 {
            return "Resets in <1m"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        var parts: [String] = []

        if days > 0 {
            parts.append("\(days)d")
        }

        if hours > 0 || days > 0 {
            parts.append("\(hours)h")
        }

        if days == 0 {
            parts.append("\(minutes)m")
        }

        return "Resets in \(parts.joined(separator: " "))"
    }

    static func absoluteResetText(
        resetDate: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Resets at \(formatter.string(from: resetDate))"
    }

    static func creditsText(from credits: CreditsInfo?) -> String {
        guard let credits else {
            return "Unavailable"
        }

        if credits.unlimited == true {
            return "Unlimited"
        }

        if let balance = credits.balance?.stringValue, balance.isEmpty == false {
            return balance
        }

        if credits.hasCredits == false {
            return "0"
        }

        return "Unavailable"
    }

    static func level(for remainingPercent: Int?) -> UsageLevel {
        guard let remainingPercent else {
            return .neutral
        }

        switch remainingPercent {
        case 51...:
            return .good
        case 21...50:
            return .warning
        default:
            return .critical
        }
    }

    static func statusBarLabel(
        snapshot: UsageSnapshot?,
        mode: StatusBarDisplayMode,
        state: UsageLoadState
    ) -> String {
        guard let snapshot else {
            return mode == .minimal ? "•" : fallbackLabel(for: state)
        }

        switch mode {
        case .fiveHourRemaining:
            return percentLabel(for: snapshot.fiveHourSection.remainingPercent)
        case .weekRemaining:
            return percentLabel(for: snapshot.weeklySection.remainingPercent)
        case .both:
            return "\(compactPercentLabel(for: snapshot.fiveHourSection.remainingPercent))/\(compactPercentLabel(for: snapshot.weeklySection.remainingPercent))"
        case .credits:
            return creditsStatusLabel(from: snapshot.creditsText)
        case .minimal:
            return "•"
        }
    }

    static func lastUpdatedText(from date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func percentLabel(for remainingPercent: Int?) -> String {
        guard let remainingPercent else {
            return "--"
        }

        return "\(remainingPercent)%"
    }

    private static func compactPercentLabel(for remainingPercent: Int?) -> String {
        guard let remainingPercent else {
            return "--"
        }

        return String(remainingPercent)
    }

    private static func creditsStatusLabel(from creditsText: String) -> String {
        if creditsText == "Unlimited" || creditsText == "Unavailable" {
            return creditsText
        }

        return "\(creditsText) cr"
    }

    private static func fallbackLabel(for state: UsageLoadState) -> String {
        switch state {
        case .loading:
            "…"
        default:
            "--"
        }
    }
}
