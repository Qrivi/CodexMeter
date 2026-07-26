import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct CLICommandRunnerTests {
    @Test
    func helpAndVersionDoNotFetchUsage() async {
        let fetcher = MockUsageFetcher(results: [])
        let runner = CodexMeterCLICommandRunner(usageService: fetcher, version: "1.2.3")

        let help = await runner.run(arguments: ["--help"], standardOutputIsTerminal: false)
        let version = await runner.run(arguments: ["--version"], standardOutputIsTerminal: false)

        #expect(help.exitCode == 0)
        #expect(help.standardOutput.contains("Usage: codexmeter"))
        #expect(version.standardOutput == "codexmeter 1.2.3\n")
    }

    @Test
    func textHidesUnavailableMetersWhileJSONPreservesThem() async throws {
        let unavailable = UsageMeterViewData(
            id: .secondary,
            kind: .rateLimit,
            title: "Secondary window",
            valueText: "Unavailable",
            resetText: nil,
            remainingPercent: nil,
            level: .neutral,
            resetDate: nil,
            isAvailable: false
        )
        let base = makeSnapshot()
        let snapshot = UsageSnapshot(
            meters: [base.meter(id: .primary)!, unavailable, base.meter(id: .credits)!],
            lastUpdated: base.lastUpdated,
            warningMessage: nil
        )
        let fetcher = MockUsageFetcher(results: [.success(snapshot), .success(snapshot)])
        let runner = CodexMeterCLICommandRunner(usageService: fetcher, version: "1.0")

        let text = await runner.run(arguments: [], standardOutputIsTerminal: false)
        let json = await runner.run(arguments: ["--json"], standardOutputIsTerminal: false)

        #expect(text.standardOutput.contains("Secondary window") == false)
        #expect(json.standardOutput.contains("\"available\" : false"))
        #expect(json.standardOutput.contains("\"id\" : \"codex.secondary\""))
    }

    @Test
    func selectsMetersByStableIDAndRejectsUnknownIDs() async {
        let snapshot = makeSnapshot()
        let fetcher = MockUsageFetcher(results: [.success(snapshot), .success(snapshot)])
        let runner = CodexMeterCLICommandRunner(usageService: fetcher, version: "1.0")

        let selected = await runner.run(
            arguments: ["--meter", "credits"],
            standardOutputIsTerminal: false
        )
        let unknown = await runner.run(
            arguments: ["--meter", "missing"],
            standardOutputIsTerminal: false
        )

        #expect(selected.standardOutput.contains("Credits remaining"))
        #expect(selected.standardOutput.contains("5 hour limit") == false)
        #expect(unknown.exitCode == 1)
        #expect(unknown.standardError.contains("Unknown meter ID"))
    }

    @Test
    func listsStableMeterIDsAndAvailability() async {
        let snapshot = makeSnapshot()
        let runner = CodexMeterCLICommandRunner(
            usageService: MockUsageFetcher(results: [.success(snapshot)]),
            version: "1.0"
        )

        let result = await runner.run(
            arguments: ["--list-meters"],
            standardOutputIsTerminal: false
        )

        #expect(result.standardOutput.contains("codex.primary\t5 hour limit\tavailable"))
        #expect(result.standardOutput.contains("credits\tCredits remaining\tavailable"))
    }

    @Test
    func usesDocumentedExitCodesAndStreams() async {
        let parseFailure = await CodexMeterCLICommandRunner(
            usageService: MockUsageFetcher(results: []),
            version: "1.0"
        ).run(arguments: ["--wat"], standardOutputIsTerminal: false)
        let runtimeFailure = await CodexMeterCLICommandRunner(
            usageService: MockUsageFetcher(results: [.failure(UsageServiceError.unauthorized)]),
            version: "1.0"
        ).run(arguments: [], standardOutputIsTerminal: false)

        #expect(parseFailure.exitCode == 2)
        #expect(parseFailure.standardOutput.isEmpty)
        #expect(parseFailure.standardError.contains("Unknown option"))
        #expect(runtimeFailure.exitCode == 1)
        #expect(runtimeFailure.standardOutput.isEmpty)
        #expect(runtimeFailure.standardError.contains("Auth token unavailable"))
    }
}
