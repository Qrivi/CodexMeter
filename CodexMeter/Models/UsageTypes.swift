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

enum UsageLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
    case authFailure(message: String)
}

enum UsageLevel: String, Equatable, Sendable {
    case good
    case warning
    case critical
    case neutral
}

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

    nonisolated var notificationTitle: String {
        switch self {
        case .fiveHour:
            "Codex 5 hour usage limit is low"
        case .weekly:
            "Codex weekly usage limit is low"
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
    let authGuidanceMessage: String?

    func withMessages(
        warningMessage: String? = nil,
        authGuidanceMessage: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourSection: fiveHourSection,
            weeklySection: weeklySection,
            creditsText: creditsText,
            lastUpdated: lastUpdated,
            warningMessage: warningMessage,
            authGuidanceMessage: authGuidanceMessage
        )
    }
}

struct AuthSession: Sendable {
    let accessToken: String
    let accountID: String?
}

protocol TokenProviding: Sendable {
    func currentSession() async throws -> AuthSession
}

protocol UsageFetching: Sendable {
    func fetchUsageSnapshot() async throws -> UsageSnapshot
}

protocol AppLaunching: Sendable {
    func openUsageDashboard() async -> Bool
    func openCodex() async -> Bool
}

protocol NotificationScheduling: Sendable {
    func requestAuthorizationIfNeeded() async -> Bool
    func updateThreshold(_ threshold: NotificationThreshold?) async
    func evaluateNotifications(for snapshot: UsageSnapshot, threshold: NotificationThreshold?) async
}

enum AuthTokenProviderError: LocalizedError, Equatable, Sendable {
    case fileMissing
    case unreadableFile
    case invalidFormat
    case missingToken

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            "Auth token file not found."
        case .unreadableFile:
            "Auth token file could not be read."
        case .invalidFormat:
            "Auth token file is invalid."
        case .missingToken:
            "Auth token is missing."
        }
    }
}

enum UsageServiceError: LocalizedError, Equatable, Sendable {
    case auth(AuthTokenProviderError)
    case unauthorized
    case network(String)
    case invalidResponse
    case decoding

    var errorDescription: String? {
        switch self {
        case .auth:
            "Authentication failed."
        case .unauthorized:
            "Usage request was unauthorized."
        case let .network(message):
            message
        case .invalidResponse:
            "The usage service returned an invalid response."
        case .decoding:
            "The usage response could not be decoded."
        }
    }

    var userFacingMessage: String {
        switch self {
        case .auth, .unauthorized:
            "Auth token unavailable. Open Codex to refresh it."
        case let .network(message):
            message
        case .invalidResponse:
            "Usage data is temporarily unavailable."
        case .decoding:
            "Usage data could not be read."
        }
    }
}

struct UsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: RateLimitInfo?
    let credits: CreditsInfo?
}

struct RateLimitInfo: Decodable, Sendable {
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
}

struct UsageWindow: Decodable, Sendable {
    let usedPercent: Double?
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: TimeInterval?
}

struct CreditsInfo: Decodable, Sendable {
    let unlimited: Bool?
    let balance: FlexibleValue?
    let hasCredits: Bool?
}

enum FlexibleValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var stringValue: String {
        switch self {
        case let .string(value):
            value
        case let .int(value):
            String(value)
        case let .double(value):
            if value.rounded() == value {
                String(Int(value))
            } else {
                String(value)
            }
        case let .bool(value):
            value ? "true" : "false"
        }
    }
}

extension FlexibleValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }

        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }

        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }

        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }

        throw DecodingError.typeMismatch(
            FlexibleValue.self,
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported value type.")
        )
    }
}
