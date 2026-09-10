import Darwin
import Foundation

@main
struct CodexMeterCommand {
    static func main() async {
        let runner = CodexMeterCLICommandRunner(
            usageService: UsageService(tokenProvider: AuthTokenProvider()),
            version: commandVersion()
        )
        let execution = await runner.run(
            arguments: Array(CommandLine.arguments.dropFirst()),
            standardOutputIsTerminal: isatty(STDOUT_FILENO) == 1
        )

        FileHandle.standardOutput.write(execution.standardOutput)
        FileHandle.standardError.write(execution.standardError)

        if execution.exitCode != 0 {
            Darwin.exit(execution.exitCode)
        }
    }

    private static func commandVersion() -> String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let contentsURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = contentsURL.appending(path: "Info.plist")

        guard let data = try? Data(contentsOf: infoPlistURL),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = propertyList as? [String: Any],
              let version = dictionary["CFBundleShortVersionString"] as? String else {
            return "development"
        }

        return version
    }
}

private extension FileHandle {
    func write(_ string: String) {
        guard string.isEmpty == false, let data = string.data(using: .utf8) else {
            return
        }
        write(data)
    }
}
