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
    func prefersBundleIdentifierWhenOpeningCodex() async {
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
            urlOpener: { _ in true },
            applicationOpener: { url in
                tracker.recordURL(url)
                return true
            }
        )

        let success = await launcher.openCodex()

        #expect(success)
        #expect(tracker.steps == ["com.openai.codex"])
        #expect(tracker.urls == [bundleURL])
    }
}
