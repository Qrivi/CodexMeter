enum AppUpdateStatus: Equatable {
    case unavailable
    case notChecked
    case checking
    case current
    case available(version: String)
    case noUpdateAvailable
    case failed
}
