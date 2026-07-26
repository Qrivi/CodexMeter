import Foundation

struct UsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: RateLimitInfo?
    let additionalRateLimits: [AdditionalRateLimitInfo]?
    let credits: CreditsInfo?
}

struct AdditionalRateLimitInfo: Decodable, Sendable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: RateLimitInfo?
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
