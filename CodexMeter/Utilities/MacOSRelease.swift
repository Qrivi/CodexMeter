import Foundation

enum MacOSRelease {
    static var isSequoia: Bool {
        isSequoia(ProcessInfo.processInfo.operatingSystemVersion)
    }

    static var isTahoe: Bool {
        isTahoe(ProcessInfo.processInfo.operatingSystemVersion)
    }

    static func isSequoia(_ version: OperatingSystemVersion) -> Bool {
        version.majorVersion == 15
    }

    static func isTahoe(_ version: OperatingSystemVersion) -> Bool {
        version.majorVersion == 26
    }
}
