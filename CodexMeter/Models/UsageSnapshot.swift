import Foundation

struct UsageMeterID: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
    let rawValue: String

    var id: String { rawValue }

    static let primary = UsageMeterID(rawValue: "codex.primary")
    static let secondary = UsageMeterID(rawValue: "codex.secondary")
    static let credits = UsageMeterID(rawValue: "credits")

    static func additional(feature: String) -> UsageMeterID {
        UsageMeterID(rawValue: "additional.\(feature)")
    }
}

enum RateLimitWindowSlot: String, Sendable {
    case primary
    case secondary

    var fallbackTitle: String {
        switch self {
        case .primary:
            "Main window"
        case .secondary:
            "Secondary window"
        }
    }
}

enum UsageMeterKind: Equatable, Sendable {
    case rateLimit
    case credits
}

struct UsageMeterViewData: Equatable, Identifiable, Sendable {
    let id: UsageMeterID
    let kind: UsageMeterKind
    let title: String
    let valueText: String
    let resetText: String?
    let remainingPercent: Int?
    let level: UsageLevel
    let resetDate: Date?
    let isAvailable: Bool

    nonisolated var supportsNotifications: Bool {
        switch kind {
        case .rateLimit:
            true
        case .credits:
            false
        }
    }
}

struct UsageSnapshot: Equatable, Sendable {
    let meters: [UsageMeterViewData]
    let lastUpdated: Date
    let warningMessage: String?

    func meter(id: UsageMeterID) -> UsageMeterViewData? {
        meters.first { $0.id == id }
    }

    var mainRateLimitMeters: [UsageMeterViewData] {
        [.primary, .secondary].compactMap { meter(id: $0) }
    }

    var additionalRateLimitMeters: [UsageMeterViewData] {
        meters.filter { $0.id.rawValue.hasPrefix("additional.") }
    }

    var creditsMeter: UsageMeterViewData? {
        meter(id: .credits)
    }

    func withMessages(warningMessage: String? = nil) -> UsageSnapshot {
        UsageSnapshot(
            meters: meters,
            lastUpdated: lastUpdated,
            warningMessage: warningMessage
        )
    }
}
