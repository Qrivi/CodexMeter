import Foundation

enum UsageFormatting {
    static func snapshot(from response: UsageResponse, now: Date = Date()) -> UsageSnapshot {
        var meters = [
            rateLimitMeter(
                id: .primary,
                window: response.rateLimit?.primaryWindow,
                slot: .primary,
                now: now
            ),
            rateLimitMeter(
                id: .secondary,
                window: response.rateLimit?.secondaryWindow,
                slot: .secondary,
                now: now
            )
        ]

        for (index, additionalLimit) in (response.additionalRateLimits ?? []).enumerated() {
            let displayName = nonEmpty(additionalLimit.limitName) ?? "Additional usage"
            let feature = nonEmpty(additionalLimit.meteredFeature)
                ?? "unknown-\(index)"
            let windowCandidates: [(slot: RateLimitWindowSlot, window: UsageWindow?)] = [
                (.primary, additionalLimit.rateLimit?.primaryWindow),
                (.secondary, additionalLimit.rateLimit?.secondaryWindow)
            ]
            let windows = windowCandidates.compactMap { candidate in
                candidate.window.map { (slot: candidate.slot, window: $0) }
            }

            for candidate in windows {
                let title = additionalMeterTitle(
                    displayName: displayName,
                    window: candidate.window,
                    slot: candidate.slot,
                    showsDuration: windows.count > 1
                )
                meters.append(rateLimitMeter(
                    id: .additional(feature: feature, slot: candidate.slot),
                    window: candidate.window,
                    slot: candidate.slot,
                    namePrefix: title,
                    now: now
                ))
            }
        }

        let creditsValue = creditsText(from: response.credits)
        meters.append(UsageMeterViewData(
            id: .credits,
            kind: .credits,
            title: "Credits remaining",
            valueText: creditsValue,
            resetText: nil,
            remainingPercent: nil,
            level: .neutral,
            resetDate: nil,
            isAvailable: creditsValue != "Unavailable"
        ))

        return UsageSnapshot(meters: meters, lastUpdated: now, warningMessage: nil)
    }

    static func additionalMeterTitle(
        displayName: String,
        window: UsageWindow,
        slot: RateLimitWindowSlot,
        showsDuration: Bool
    ) -> String {
        guard showsDuration else {
            return displayName
        }

        let duration = windowDurationTitle(for: window) ?? slot.fallbackTitle
        return "\(displayName) · \(duration)"
    }

    static func rateLimitMeter(
        id: UsageMeterID,
        window: UsageWindow?,
        slot: RateLimitWindowSlot,
        namePrefix: String? = nil,
        now: Date = Date()
    ) -> UsageMeterViewData {
        let title = meterTitle(for: window, slot: slot, namePrefix: namePrefix)
        let compactTitle = window.flatMap {
            compactWindowDurationTitle(for: $0)
        }
        guard let window,
              let remainingPercent = remainingPercent(from: window.usedPercent) else {
            return UsageMeterViewData(
                id: id,
                kind: .rateLimit,
                title: title,
                valueText: "Unavailable",
                resetText: nil,
                remainingPercent: nil,
                level: .neutral,
                resetDate: nil,
                isAvailable: false,
                compactTitle: compactTitle
            )
        }

        let resetDate = resetDate(for: window, now: now)

        return UsageMeterViewData(
            id: id,
            kind: .rateLimit,
            title: title,
            valueText: "\(remainingPercent)% remaining",
            resetText: resetText(resetDate: resetDate, now: now),
            remainingPercent: remainingPercent,
            level: level(for: remainingPercent),
            resetDate: resetDate,
            isAvailable: true,
            compactTitle: compactTitle
        )
    }

    static func meterTitle(
        for window: UsageWindow?,
        slot: RateLimitWindowSlot,
        namePrefix: String? = nil
    ) -> String {
        if let namePrefix {
            return namePrefix
        }

        let duration: String
        if let window {
            duration = windowDurationTitle(for: window) ?? slot.fallbackTitle
        } else {
            duration = slot.fallbackTitle
        }
        return duration
    }

    static func windowDurationTitle(for window: UsageWindow) -> String? {
        if let seconds = window.limitWindowSeconds,
           let title = durationTitle(seconds: seconds) {
            return title
        }

        // reset_after_seconds is time remaining, so it is only safe as a fallback
        // when it exactly identifies one of the common window durations.
        switch window.resetAfterSeconds {
        case 18_000:
            return "5 hour limit"
        case 86_400:
            return "Daily limit"
        case 604_800:
            return "Weekly limit"
        default:
            return nil
        }
    }

    static func compactWindowDurationTitle(for window: UsageWindow) -> String? {
        windowDurationTitle(for: window)?
            .replacingOccurrences(of: " limit", with: "")
    }

    static func durationTitle(seconds: Int) -> String? {
        guard seconds > 0 else {
            return nil
        }

        if seconds == 604_800 {
            return "Weekly limit"
        }

        if seconds == 86_400 {
            return "Daily limit"
        }

        if seconds.isMultiple(of: 86_400) {
            let days = seconds / 86_400
            return "\(days) day limit"
        }

        if seconds.isMultiple(of: 3_600) {
            let hours = seconds / 3_600
            return "\(hours) hour limit"
        }

        if seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return "\(minutes) minute limit"
        }

        return nil
    }

    static func remainingPercent(from usedPercent: Double?) -> Int? {
        guard let usedPercent else {
            return nil
        }

        let used = Int(usedPercent.rounded())
        return max(0, min(100, 100 - used))
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

        let absolute = absoluteResetText(resetDate: resetDate, now: now, locale: locale, timeZone: timeZone)
        let relative = relativeResetText(resetDate: resetDate, now: now)
        return "\(absolute) (\(relative))"
    }

    static func relativeResetText(resetDate: Date, now: Date = Date()) -> String {
        let seconds = max(Int(resetDate.timeIntervalSince(now)), 0)

        if seconds < 60 {
            return "<1m"
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

        return parts.joined(separator: " ")
    }

    static func absoluteResetText(
        resetDate: Date,
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let calendar = calendar(locale: locale, timeZone: timeZone)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        if calendar.isDate(resetDate, inSameDayAs: now) {
            return "Resets \(timeFormatter.string(from: resetDate))"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "MMMM d, yyyy"
        return "Resets \(dateFormatter.string(from: resetDate)) \(timeFormatter.string(from: resetDate))"
    }

    private static func calendar(locale: Locale, timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
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

    static func menuBarLabel(
        snapshot: UsageSnapshot?,
        mode: MenuBarDisplayMode,
        state: UsageLoadState
    ) -> String {
        menuBarLabelSegments(snapshot: snapshot, mode: mode, colorMode: .monochrome, state: state)
            .map(\.text)
            .joined()
    }

    static func menuBarTitle(
        snapshot: UsageSnapshot?,
        mode: MenuBarDisplayMode
    ) -> String {
        switch mode {
        case .both:
            "Limits"
        case .credits:
            "Credits"
        case .primaryRemaining:
            snapshot?.meter(id: .primary)?.compactTitle ?? "Limits"
        case .secondaryRemaining:
            snapshot?.meter(id: .secondary)?.compactTitle ?? "Limits"
        case let .meter(meterID):
            snapshot?.meter(id: meterID)?.compactTitle ?? "Limits"
        }
    }

    static func menuBarLabelSegments(
        snapshot: UsageSnapshot?,
        mode: MenuBarDisplayMode,
        colorMode: UsageColorMode,
        state: UsageLoadState
    ) -> [MenuBarLabelSegment] {
        if let errorLabel = menuBarErrorLabel(snapshot: snapshot, state: state) {
            return [MenuBarLabelSegment(text: errorLabel, tone: .critical)]
        }

        guard let snapshot else {
            return [MenuBarLabelSegment(text: fallbackLabel(for: state), tone: .neutral)]
        }

        switch mode {
        case .primaryRemaining:
            return [meterSegment(for: snapshot.meter(id: .primary), colorMode: colorMode)]
        case .secondaryRemaining:
            return [meterSegment(for: snapshot.meter(id: .secondary), colorMode: colorMode)]
        case .both:
            let availableMeters = [snapshot.meter(id: .primary), snapshot.meter(id: .secondary)]
                .compactMap { $0 }
                .filter(\.isAvailable)
            guard availableMeters.isEmpty == false else {
                return [MenuBarLabelSegment(text: "--", tone: .neutral)]
            }

            return availableMeters.enumerated().flatMap { index, meter in
                let segment = meterSegment(for: meter, colorMode: colorMode)
                return index == 0
                    ? [segment]
                    : [MenuBarLabelSegment(text: "/", tone: .neutral), segment]
            }
        case .credits:
            let value = snapshot.meter(id: .credits)?.valueText ?? "Unavailable"
            return [MenuBarLabelSegment(text: creditsStatusLabel(from: value), tone: .neutral)]
        case let .meter(meterID):
            return [meterSegment(for: snapshot.meter(id: meterID), colorMode: colorMode)]
        }
    }

    static func menuBarErrorLabel(snapshot: UsageSnapshot?, state: UsageLoadState) -> String? {
        switch state {
        case .failed:
            return "Error"
        default:
            break
        }

        if snapshot?.warningMessage != nil {
            return "Error"
        }

        return nil
    }

    static func menuBarTone(
        for section: UsageMeterViewData,
        colorMode: UsageColorMode
    ) -> MenuBarTextTone {
        switch colorMode {
        case .monochrome:
            return .neutral
        case .colorful:
            return menuBarTone(for: section.level)
        case .colorfulWhenLow:
            guard let remainingPercent = section.remainingPercent, remainingPercent <= NotificationThreshold.twenty.rawValue else {
                return .neutral
            }

            return .critical
        }
    }

    static func lastUpdatedText(
        from date: Date,
        now: Date = Date(),
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let calendar = calendar(locale: locale, timeZone: timeZone)
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        if calendar.isDate(date, inSameDayAs: now) {
            return timeFormatter.string(from: date)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "MMM d, yyyy"
        return "\(dateFormatter.string(from: date)) \(timeFormatter.string(from: date))"
    }

    private static func percentLabel(for remainingPercent: Int?) -> String {
        guard let remainingPercent else {
            return "--"
        }

        return "\(remainingPercent)%"
    }

    private static func meterSegment(
        for section: UsageMeterViewData?,
        colorMode: UsageColorMode
    ) -> MenuBarLabelSegment {
        guard let section else {
            return MenuBarLabelSegment(text: "--", tone: .neutral)
        }

        return MenuBarLabelSegment(
            text: percentLabel(for: section.remainingPercent),
            tone: menuBarTone(for: section, colorMode: colorMode)
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        return value
    }

    private static func menuBarTone(for level: UsageLevel) -> MenuBarTextTone {
        switch level {
        case .good:
            return .good
        case .warning:
            return .warning
        case .critical:
            return .critical
        case .neutral:
            return .neutral
        }
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
