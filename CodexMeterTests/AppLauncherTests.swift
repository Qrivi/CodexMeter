import Foundation
import Testing
@testable import CodexMeter

@MainActor
struct AppLauncherTests {
    @Test
    func opensDashboardURL() async {
        let tracker = LauncherRecorder()
        let launcher = AppLauncher(
            bundleIdentifierResolver: { _ in nil },
            fallbackURLResolver: { nil },
            urlOpener: { url in
                tracker.recordURL(url)
                return true
            },
            applicationOpener: { _ in true }
        )

        let success = await launcher.openUsageDashboard()

        #expect(success)
        #expect(tracker.urls == [AppLauncher.usageDashboardURL])
    }

    @Test
    func opensCodexURLSchemeBeforeResolvingAppBundle() async {
        let tracker = LauncherRecorder()
        let launcher = AppLauncher(
            bundleIdentifierResolver: { identifier in
                tracker.recordStep(identifier)
                return URL(fileURLWithPath: "/Applications/Codex.app")
            },
            fallbackURLResolver: {
                tracker.recordStep("fallback")
                return URL(fileURLWithPath: "/Fallback/Codex.app")
            },
            urlOpener: { url in
                tracker.recordURL(url)
                return true
            },
            applicationOpener: { url in
                tracker.recordURL(url)
                return true
            }
        )

        let success = await launcher.openCodex()

        #expect(success)
        #expect(tracker.steps.isEmpty)
        #expect(tracker.urls == [AppLauncher.codexURL])
    }

    @Test
    func fallsBackToBundleIdentifierWhenCodexURLSchemeFails() async {
        let tracker = LauncherRecorder()
        let bundleURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let launcher = AppLauncher(
            bundleIdentifierResolver: { identifier in
                tracker.recordStep(identifier)
                return bundleURL
            },
            fallbackURLResolver: {
                tracker.recordStep("fallback")
                return URL(fileURLWithPath: "/Fallback/Codex.app")
            },
            urlOpener: { url in
                tracker.recordURL(url)
                return false
            },
            applicationOpener: { url in
                tracker.recordURL(url)
                return true
            }
        )

        let success = await launcher.openCodex()

        #expect(success)
        #expect(tracker.steps == [AppLauncher.codexBundleIdentifier])
        #expect(tracker.urls == [AppLauncher.codexURL, bundleURL])
    }

    @Test
    func fallsBackToCodexAppPathWhenURLSchemeAndBundleIdentifierFail() async {
        let tracker = LauncherRecorder()
        let fallbackURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let launcher = AppLauncher(
            bundleIdentifierResolver: { identifier in
                tracker.recordStep(identifier)
                return nil
            },
            fallbackURLResolver: {
                tracker.recordStep("fallback")
                return fallbackURL
            },
            urlOpener: { url in
                tracker.recordURL(url)
                return false
            },
            applicationOpener: { url in
                tracker.recordURL(url)
                return true
            }
        )

        let success = await launcher.openCodex()

        #expect(success)
        #expect(tracker.steps == [AppLauncher.codexBundleIdentifier, "fallback"])
        #expect(tracker.urls == [AppLauncher.codexURL, fallbackURL])
    }
}
