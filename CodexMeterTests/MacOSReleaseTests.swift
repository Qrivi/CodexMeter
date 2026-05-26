import Foundation
import Testing
@testable import CodexMeter

struct MacOSReleaseTests {
    @Test
    func detectsSequoiaByMajorVersion() {
        let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 2)

        #expect(MacOSRelease.isSequoia(sequoia))
        #expect(MacOSRelease.isTahoe(sequoia) == false)
    }

    @Test
    func detectsTahoeByMajorVersion() {
        let tahoe = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 1)

        #expect(MacOSRelease.isTahoe(tahoe))
        #expect(MacOSRelease.isSequoia(tahoe) == false)
    }

    @Test
    func treatsOtherMajorVersionsAsNeitherRelease() {
        let futureRelease = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)

        #expect(MacOSRelease.isSequoia(futureRelease) == false)
        #expect(MacOSRelease.isTahoe(futureRelease) == false)
    }
}
