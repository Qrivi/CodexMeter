import Foundation

struct CLIInstallLocation: Hashable, Identifiable {
    let path: String

    var id: String { path }

    static let standardLocations: [CLIInstallLocation] = [
        CLIInstallLocation(path: "~/.local/bin"),
        CLIInstallLocation(path: "/opt/homebrew/bin"),
        CLIInstallLocation(path: "/usr/local/bin"),
        CLIInstallLocation(path: "~/bin")
    ]

    static var `default`: CLIInstallLocation {
        standardLocations[0]
    }

    var expandedPath: String {
        NSString(string: path).expandingTildeInPath
    }

    var isUserLocation: Bool {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        return normalizedPath == homePath || normalizedPath.hasPrefix(homePath + "/")
    }
}

enum CLIInstallState: Equatable {
    case installed
    case notInstalled
    case missingDirectory
    case permissionDenied
    case existingFile
    case foreignSymlink
    case staleCodexMeterSymlink
    case missingBundledCLI
}

struct CLIInstallStatus: Equatable {
    let state: CLIInstallState
    let message: String

    var isInstalled: Bool {
        state == .installed
    }

    var canInstall: Bool {
        switch state {
        case .notInstalled, .missingDirectory, .staleCodexMeterSymlink:
            true
        case .installed, .permissionDenied, .existingFile, .foreignSymlink, .missingBundledCLI:
            false
        }
    }
}

enum CLIInstallServiceError: LocalizedError, Equatable {
    case missingBundledCLI
    case missingDirectory(String)
    case permissionDenied(String)
    case existingFile(String)
    case foreignSymlink(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledCLI:
            "The bundled codexmeter command was not found."
        case let .missingDirectory(path):
            "\(path) does not exist."
        case let .permissionDenied(path):
            "CodexMeter cannot write to \(path)."
        case let .existingFile(path):
            "\(path) already exists and is not a symbolic link."
        case let .foreignSymlink(path):
            "\(path) is a symbolic link managed by something else."
        case let .failed(message):
            message
        }
    }
}

struct CLIInstallService {
    let cliURL: URL
    let fileManager: FileManager

    init(
        cliURL: URL = Bundle.main.bundleURL
            .appending(path: "Contents")
            .appending(path: "Helpers")
            .appending(path: "codexmeter"),
        fileManager: FileManager = .default
    ) {
        self.cliURL = cliURL
        self.fileManager = fileManager
    }

    func status(for location: CLIInstallLocation) -> CLIInstallStatus {
        guard fileManager.fileExists(atPath: cliURL.path) else {
            return CLIInstallStatus(
                state: .missingBundledCLI,
                message: "The bundled CLI was not found in this copy of CodexMeter."
            )
        }

        guard fileManager.directoryExists(atPath: location.expandedPath) else {
            if location.isUserLocation {
                return CLIInstallStatus(
                    state: .missingDirectory,
                    message: "\(location.path) will be created when the CLI is installed."
                )
            }
            return CLIInstallStatus(
                state: .missingDirectory,
                message: "\(location.path) does not exist."
            )
        }

        let linkURL = linkURL(for: location)

        guard fileManager.itemExistsIncludingSymbolicLink(atPath: linkURL.path) else {
            guard fileManager.isWritableDirectory(atPath: location.expandedPath) else {
                return CLIInstallStatus(
                    state: .permissionDenied,
                    message: "CodexMeter cannot write to \(location.path)."
                )
            }

            return CLIInstallStatus(
                state: .notInstalled,
                message: "The CLI is not installed in \(location.path)."
            )
        }

        guard fileManager.isSymbolicLink(atPath: linkURL.path) else {
            return CLIInstallStatus(
                state: .existingFile,
                message: "\(linkURL.path) already exists and will not be replaced."
            )
        }

        if symbolicLink(at: linkURL, pointsTo: cliURL) {
            return CLIInstallStatus(
                state: .installed,
                message: "The CLI is installed in \(location.path)."
            )
        }

        if isStaleCodexMeterLink(at: linkURL) {
            return CLIInstallStatus(
                state: .staleCodexMeterSymlink,
                message: "The existing CodexMeter symlink points to an older app location."
            )
        }

        return CLIInstallStatus(
            state: .foreignSymlink,
            message: "\(linkURL.path) is managed by something else and will not be replaced."
        )
    }

    func install(in location: CLIInstallLocation) throws {
        guard fileManager.fileExists(atPath: cliURL.path) else {
            throw CLIInstallServiceError.missingBundledCLI
        }

        if fileManager.directoryExists(atPath: location.expandedPath) == false {
            guard location.isUserLocation else {
                throw CLIInstallServiceError.missingDirectory(location.path)
            }

            do {
                try fileManager.createDirectory(
                    at: URL(fileURLWithPath: location.expandedPath),
                    withIntermediateDirectories: true
                )
            } catch {
                throw CLIInstallServiceError.failed(error.localizedDescription)
            }
        }

        guard fileManager.isWritableDirectory(atPath: location.expandedPath) else {
            throw CLIInstallServiceError.permissionDenied(location.path)
        }

        let linkURL = linkURL(for: location)
        if fileManager.itemExistsIncludingSymbolicLink(atPath: linkURL.path) {
            guard fileManager.isSymbolicLink(atPath: linkURL.path) else {
                throw CLIInstallServiceError.existingFile(linkURL.path)
            }

            if symbolicLink(at: linkURL, pointsTo: cliURL) {
                return
            }

            guard isStaleCodexMeterLink(at: linkURL) else {
                throw CLIInstallServiceError.foreignSymlink(linkURL.path)
            }

            do {
                try fileManager.removeItem(at: linkURL)
            } catch {
                throw CLIInstallServiceError.failed(error.localizedDescription)
            }
        }

        do {
            try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: cliURL)
        } catch {
            throw CLIInstallServiceError.failed(error.localizedDescription)
        }
    }

    func remove(from location: CLIInstallLocation) throws {
        let linkURL = linkURL(for: location)
        guard fileManager.isSymbolicLink(atPath: linkURL.path),
              symbolicLink(at: linkURL, pointsTo: cliURL) else {
            return
        }

        do {
            try fileManager.removeItem(at: linkURL)
        } catch {
            throw CLIInstallServiceError.failed(error.localizedDescription)
        }
    }

    func manualInstallCommand(for location: CLIInstallLocation) -> String {
        let linkCommand = "ln -s \(shellQuoted(cliURL.path)) \(shellQuoted(linkURL(for: location).path))"
        guard fileManager.directoryExists(atPath: location.expandedPath) == false,
              location.isUserLocation else {
            return linkCommand
        }

        return "mkdir -p \(shellQuoted(location.expandedPath)) && \(linkCommand)"
    }

    func linkURL(for location: CLIInstallLocation) -> URL {
        URL(fileURLWithPath: location.expandedPath).appending(path: "codexmeter")
    }

    private func isStaleCodexMeterLink(at linkURL: URL) -> Bool {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) else {
            return false
        }

        return destination.hasSuffix("/CodexMeter.app/Contents/Helpers/codexmeter")
    }

    private func symbolicLink(at linkURL: URL, pointsTo destinationURL: URL) -> Bool {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path) else {
            return false
        }

        let resolvedDestination: URL
        if destination.hasPrefix("/") {
            resolvedDestination = URL(fileURLWithPath: destination)
        } else {
            resolvedDestination = linkURL.deletingLastPathComponent().appending(path: destination)
        }

        return resolvedDestination.standardizedFileURL.path == destinationURL.standardizedFileURL.path
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func isWritableDirectory(atPath path: String) -> Bool {
        directoryExists(atPath: path) && isWritableFile(atPath: path)
    }

    func isSymbolicLink(atPath path: String) -> Bool {
        (try? destinationOfSymbolicLink(atPath: path)) != nil
    }

    func itemExistsIncludingSymbolicLink(atPath path: String) -> Bool {
        fileExists(atPath: path) || isSymbolicLink(atPath: path)
    }
}
