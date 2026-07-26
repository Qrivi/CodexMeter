import Foundation

struct CodexMeterCLIJSONRenderer: Sendable {
    nonisolated func render(snapshot: UsageSnapshot, meters: [UsageMeterViewData]) throws -> String {
        let payload = CodexMeterCLIJSONPayload(snapshot: snapshot, meters: meters)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }
}

private nonisolated struct CodexMeterCLIJSONPayload: Encodable {
    let schemaVersion = 1
    let lastUpdated: Date
    let warningMessage: String?
    let meters: [Meter]

    nonisolated init(snapshot: UsageSnapshot, meters: [UsageMeterViewData]) {
        self.lastUpdated = snapshot.lastUpdated
        self.warningMessage = snapshot.warningMessage
        self.meters = meters.map(Meter.init)
    }

    nonisolated struct Meter: Encodable {
        let id: String
        let kind: String
        let title: String
        let valueText: String
        let available: Bool
        let remainingPercent: Int?
        let resetAt: Date?
        let level: String

        nonisolated init(meter: UsageMeterViewData) {
            self.id = meter.id.rawValue
            self.kind = switch meter.kind {
            case .rateLimit:
                "rate_limit"
            case .credits:
                "credits"
            }
            self.title = meter.title
            self.valueText = meter.valueText
            self.available = meter.isAvailable
            self.remainingPercent = meter.remainingPercent
            self.resetAt = meter.resetDate
            self.level = meter.level.rawValue
        }
    }
}
