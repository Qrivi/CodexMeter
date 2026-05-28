import AppKit
import Foundation

struct AppLauncher: AppLaunching {
    static let usageDashboardURL = URL(string: "https://chatgpt.com/codex/settings/usage")!
    static let codexURL = URL(string: "codex://")!
    static let codexBundleIdentifier = "com.openai.codex"
    static let codexFallbackPath = "/Applications/Codex.app"

    private let bundleIdentifierResolver: @Sendable (String) -> URL?
    private let fallbackURLResolver: @Sendable () -> URL?
    private let urlOpener: @Sendable (URL) -> Bool
    private let applicationOpener: @Sendable (URL) async -> Bool

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.bundleIdentifierResolver = { bundleIdentifier in
            workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }

        self.fallbackURLResolver = {
            let fallbackURL = URL(fileURLWithPath: Self.codexFallbackPath)
            guard fileManager.fileExists(atPath: fallbackURL.path) else {
                return nil
            }

            return fallbackURL
        }

        self.urlOpener = { url in
            workspace.open(url)
        }

        self.applicationOpener = { url in
            await MainActor.run {
                workspace.open(url)
            }
        }
    }

    init(
        bundleIdentifierResolver: @escaping @Sendable (String) -> URL?,
        fallbackURLResolver: @escaping @Sendable () -> URL?,
        urlOpener: @escaping @Sendable (URL) -> Bool,
        applicationOpener: @escaping @Sendable (URL) async -> Bool
    ) {
        self.bundleIdentifierResolver = bundleIdentifierResolver
        self.fallbackURLResolver = fallbackURLResolver
        self.urlOpener = urlOpener
        self.applicationOpener = applicationOpener
    }

    func openUsageDashboard() async -> Bool {
        urlOpener(Self.usageDashboardURL)
    }

    func openCodex() async -> Bool {
        if urlOpener(Self.codexURL) {
            return true
        }

        if let appURL = bundleIdentifierResolver(Self.codexBundleIdentifier) {
            return await applicationOpener(appURL)
        }

        if let fallbackURL = fallbackURLResolver() {
            return await applicationOpener(fallbackURL)
        }

        return false
    }
}
