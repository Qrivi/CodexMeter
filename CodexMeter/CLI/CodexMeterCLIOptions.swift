import Foundation

enum CodexMeterCLIParseError: LocalizedError, Equatable, Sendable {
    case missingValue(String)
    case unknownOption(String)
    case unexpectedArgument(String)
    case invalidFormat(String)
    case invalidColorPolicy(String)
    case emptyMeterID

    nonisolated var errorDescription: String? {
        switch self {
        case let .missingValue(option):
            "Missing value for \(option)."
        case let .unknownOption(option):
            "Unknown option: \(option)."
        case let .unexpectedArgument(argument):
            "Unexpected argument: \(argument)."
        case let .invalidFormat(value):
            "Invalid format: \(value). Use text or json."
        case let .invalidColorPolicy(value):
            "Invalid color policy: \(value). Use auto, always, or never."
        case .emptyMeterID:
            "Meter IDs cannot be empty."
        }
    }
}

struct CodexMeterCLIOptions: Equatable, Sendable {
    enum OutputFormat: String, Equatable, Sendable {
        case text
        case json
    }

    enum ColorPolicy: String, Equatable, Sendable {
        case auto
        case always
        case never
    }

    var format: OutputFormat = .text
    var meterIDs: [UsageMeterID] = []
    var colorPolicy: ColorPolicy = .auto
    var listsMeters = false
    var printsVersion = false
    var printsHelp = false

    nonisolated static func parse(_ arguments: [String]) throws -> CodexMeterCLIOptions {
        var options = CodexMeterCLIOptions()
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let argument = arguments[index]

            switch argument {
            case "-h", "--help":
                options.printsHelp = true
            case "--version":
                options.printsVersion = true
            case "-j", "--json":
                options.format = .json
            case "--no-color":
                options.colorPolicy = .never
            case "--list-meters":
                options.listsMeters = true
            case "-f", "--format":
                let value = try value(after: argument, arguments: arguments, index: &index)
                options.format = try parseFormat(value)
            case "-m", "--meter":
                let value = try value(after: argument, arguments: arguments, index: &index)
                options.meterIDs.append(try parseMeterID(value))
            case "--color":
                let value = try value(after: argument, arguments: arguments, index: &index)
                options.colorPolicy = try parseColorPolicy(value)
            default:
                if argument.hasPrefix("--format=") {
                    options.format = try parseFormat(value(afterEqualsIn: argument))
                } else if argument.hasPrefix("--meter=") {
                    options.meterIDs.append(try parseMeterID(value(afterEqualsIn: argument)))
                } else if argument.hasPrefix("--color=") {
                    options.colorPolicy = try parseColorPolicy(value(afterEqualsIn: argument))
                } else if argument.hasPrefix("-") {
                    throw CodexMeterCLIParseError.unknownOption(argument)
                } else {
                    throw CodexMeterCLIParseError.unexpectedArgument(argument)
                }
            }

            index = arguments.index(after: index)
        }

        return options
    }

    nonisolated static var helpText: String {
        """
        Usage: codexmeter [options]

        Prints the usage meters returned for the current Codex account.

        Options:
          -f, --format <text|json>       Select the output format.
          -j, --json                     Shortcut for --format json.
          -m, --meter <id>               Select a meter. May be repeated.
              --list-meters              List returned meter IDs and availability.
              --color <auto|always|never>
              --no-color                 Shortcut for --color never.
              --version                  Show the command version.
          -h, --help                     Show this help.

        Text output shows every available meter by default. JSON output includes
        unavailable meters so scripts can distinguish missing data from missing meters.
        """
    }

    private nonisolated static func value(
        after option: String,
        arguments: [String],
        index: inout Array<String>.Index
    ) throws -> String {
        let valueIndex = arguments.index(after: index)

        guard valueIndex < arguments.endIndex else {
            throw CodexMeterCLIParseError.missingValue(option)
        }

        index = valueIndex
        return arguments[valueIndex]
    }

    private nonisolated static func value(afterEqualsIn argument: String) -> String {
        String(argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).last ?? "")
    }

    private nonisolated static func parseFormat(_ value: String) throws -> OutputFormat {
        guard let format = OutputFormat(rawValue: value.lowercased()) else {
            throw CodexMeterCLIParseError.invalidFormat(value)
        }

        return format
    }

    private nonisolated static func parseColorPolicy(_ value: String) throws -> ColorPolicy {
        guard let policy = ColorPolicy(rawValue: value.lowercased()) else {
            throw CodexMeterCLIParseError.invalidColorPolicy(value)
        }

        return policy
    }

    private nonisolated static func parseMeterID(_ value: String) throws -> UsageMeterID {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw CodexMeterCLIParseError.emptyMeterID
        }

        return UsageMeterID(rawValue: normalized)
    }
}
