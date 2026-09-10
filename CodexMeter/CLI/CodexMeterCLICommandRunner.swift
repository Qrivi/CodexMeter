import Foundation

struct CodexMeterCLIExecution: Equatable, Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

struct CodexMeterCLICommandRunner: Sendable {
    private let usageService: UsageFetching
    private let version: String

    nonisolated init(usageService: UsageFetching, version: String) {
        self.usageService = usageService
        self.version = version
    }

    nonisolated func run(arguments: [String], standardOutputIsTerminal: Bool) async -> CodexMeterCLIExecution {
        let options: CodexMeterCLIOptions

        do {
            options = try CodexMeterCLIOptions.parse(arguments)
        } catch {
            return CodexMeterCLIExecution(
                exitCode: 2,
                standardOutput: "",
                standardError: "\(error.localizedDescription)\n\n\(CodexMeterCLIOptions.helpText)\n"
            )
        }

        if options.printsHelp {
            return success(CodexMeterCLIOptions.helpText)
        }

        if options.printsVersion {
            return success("codexmeter \(version)")
        }

        do {
            let snapshot = try await usageService.fetchUsageSnapshot()

            if options.listsMeters {
                return success(renderMeterList(snapshot.meters))
            }

            let selectedMeters: [UsageMeterViewData]
            do {
                selectedMeters = try meters(for: options, in: snapshot)
            } catch {
                return CodexMeterCLIExecution(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "\(error.localizedDescription)\n"
                )
            }

            switch options.format {
            case .json:
                return success(try CodexMeterCLIJSONRenderer().render(
                    snapshot: snapshot,
                    meters: selectedMeters
                ))
            case .text:
                let visibleMeters = options.meterIDs.isEmpty
                    ? selectedMeters.filter(\.isAvailable)
                    : selectedMeters
                guard visibleMeters.isEmpty == false else {
                    return success("No usage meters are currently available.")
                }

                let usesANSI = switch options.colorPolicy {
                case .auto:
                    standardOutputIsTerminal
                case .always:
                    true
                case .never:
                    false
                }
                return success(CodexMeterCLIRenderer(usesANSI: usesANSI).render(meters: visibleMeters))
            }
        } catch let error as UsageServiceError {
            return failure(error.userFacingMessage)
        } catch {
            return failure(error.localizedDescription)
        }
    }

    private nonisolated func meters(
        for options: CodexMeterCLIOptions,
        in snapshot: UsageSnapshot
    ) throws -> [UsageMeterViewData] {
        guard options.meterIDs.isEmpty == false else {
            return snapshot.meters
        }

        var selected: [UsageMeterViewData] = []
        var seen: Set<UsageMeterID> = []

        for meterID in options.meterIDs where seen.insert(meterID).inserted {
            guard let meter = snapshot.meter(id: meterID) else {
                throw CodexMeterCLISelectionError.unknownMeter(meterID.rawValue)
            }
            selected.append(meter)
        }

        return selected
    }

    private nonisolated func renderMeterList(_ meters: [UsageMeterViewData]) -> String {
        meters.map { meter in
            "\(meter.id.rawValue)\t\(meter.title)\t\(meter.isAvailable ? "available" : "unavailable")"
        }
        .joined(separator: "\n")
    }

    private nonisolated func success(_ output: String) -> CodexMeterCLIExecution {
        CodexMeterCLIExecution(
            exitCode: 0,
            standardOutput: output + "\n",
            standardError: ""
        )
    }

    private nonisolated func failure(_ message: String) -> CodexMeterCLIExecution {
        CodexMeterCLIExecution(
            exitCode: 1,
            standardOutput: "",
            standardError: message + "\n"
        )
    }
}

private enum CodexMeterCLISelectionError: LocalizedError {
    case unknownMeter(String)

    nonisolated var errorDescription: String? {
        switch self {
        case let .unknownMeter(id):
            "Unknown meter ID: \(id). Run codexmeter --list-meters to see the returned IDs."
        }
    }
}
