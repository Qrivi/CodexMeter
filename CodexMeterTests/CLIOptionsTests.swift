import Testing
@testable import CodexMeter

@MainActor
struct CLIOptionsTests {
    @Test
    func parsesDefaults() throws {
        let options = try CodexMeterCLIOptions.parse([])

        #expect(options.format == .text)
        #expect(options.meterIDs.isEmpty)
        #expect(options.colorPolicy == .auto)
        #expect(options.listsMeters == false)
        #expect(options.printsVersion == false)
        #expect(options.printsHelp == false)
    }

    @Test
    func parsesFormatsMetersAndColorPolicies() throws {
        let options = try CodexMeterCLIOptions.parse([
            "--format=json",
            "--meter", "codex.primary",
            "--meter=additional.codex_bengalfox.secondary",
            "--color", "always",
            "--list-meters"
        ])

        #expect(options.format == .json)
        #expect(options.meterIDs.map(\.rawValue) == [
            "codex.primary",
            "additional.codex_bengalfox.secondary"
        ])
        #expect(options.colorPolicy == .always)
        #expect(options.listsMeters)

        let aliases = try CodexMeterCLIOptions.parse(["--json", "--no-color"])
        #expect(aliases.format == .json)
        #expect(aliases.colorPolicy == .never)
    }

    @Test
    func rejectsInvalidArguments() {
        #expect(throws: CodexMeterCLIParseError.invalidFormat("yaml")) {
            try CodexMeterCLIOptions.parse(["--format", "yaml"])
        }
        #expect(throws: CodexMeterCLIParseError.invalidColorPolicy("sometimes")) {
            try CodexMeterCLIOptions.parse(["--color=sometimes"])
        }
        #expect(throws: CodexMeterCLIParseError.missingValue("--meter")) {
            try CodexMeterCLIOptions.parse(["--meter"])
        }
        #expect(throws: CodexMeterCLIParseError.emptyMeterID) {
            try CodexMeterCLIOptions.parse(["--meter="])
        }
    }
}
