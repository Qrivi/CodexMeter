import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct CLIRendererTests {
    @Test
    func rendersDynamicMetersAndCreditsInSnapshotOrder() {
        let additionalID = UsageMeterID.additional(
            feature: "codex_bengalfox",
            slot: .secondary
        )
        let meters = [
            makeSnapshot(fiveHourRemaining: 50).meter(id: .primary)!,
            UsageMeterViewData(
                id: additionalID,
                kind: .rateLimit,
                title: "Spark · Weekly",
                valueText: "25% remaining",
                resetText: "Resets tomorrow",
                remainingPercent: 25,
                level: .warning,
                resetDate: Date(timeIntervalSince1970: 1_778_141_800),
                isAvailable: true
            ),
            makeSnapshot().meter(id: .credits)!
        ]

        let output = CodexMeterCLIRenderer(usesANSI: false).render(meters: meters)
        let lines = output.components(separatedBy: "\n")

        #expect(lines[0] == "5 hour limit                       50% remaining")
        #expect(lines[1] == String(repeating: "█", count: 24) + String(repeating: "░", count: 24))
        #expect(output.contains("Spark · Weekly"))
        #expect(output.contains("Credits remaining"))
    }

    @Test
    func appliesANSIOnlyWhenEnabled() {
        let meter = makeSnapshot(fiveHourRemaining: 10).meter(id: .primary)!
        let colorful = CodexMeterCLIRenderer(usesANSI: true).render(meters: [meter])
        let plain = CodexMeterCLIRenderer(usesANSI: false).render(meters: [meter])

        #expect(colorful.contains("\u{001B}[38;2;224;122;122m"))
        #expect(colorful.contains("\u{001B}[2m"))
        #expect(plain.contains("\u{001B}[") == false)
    }

    @Test
    func rendersVersionedJSONMeterArray() throws {
        let snapshot = makeSnapshot()
        let json = try CodexMeterCLIJSONRenderer().render(
            snapshot: snapshot,
            meters: snapshot.meters
        )
        let data = try #require(json.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let meters = try #require(object["meters"] as? [[String: Any]])

        #expect(object["schema_version"] as? Int == 1)
        #expect(meters.count == 3)
        #expect(meters[0]["id"] as? String == "codex.primary")
        #expect(meters[0]["kind"] as? String == "rate_limit")
        #expect(meters[0]["remaining_percent"] as? Int == 64)
        #expect(meters[2]["kind"] as? String == "credits")
    }
}
