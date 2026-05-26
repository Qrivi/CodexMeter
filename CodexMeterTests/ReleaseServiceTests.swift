import Testing
@testable import CodexMeter

struct ReleaseServiceTests {
    @Test
    func normalizesGitHubTags() {
        #expect("v0.10.0".normalizedReleaseVersion == "0.10.0")
        #expect("  V1.2.3  ".normalizedReleaseVersion == "1.2.3")
    }

    @Test
    func comparesSemanticVersions() {
        #expect("0.10.0".isOlderReleaseVersion(than: "0.11.0"))
        #expect("0.10.0".isOlderReleaseVersion(than: "v0.10.1"))
        #expect("0.10.0".isOlderReleaseVersion(than: "0.10.0") == false)
        #expect("0.10.1".isOlderReleaseVersion(than: "0.10.0") == false)
        #expect("1.0".isOlderReleaseVersion(than: "1.0.0") == false)
    }
}
