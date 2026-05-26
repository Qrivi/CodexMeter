import Combine
import Foundation

@MainActor
final class AboutPaneModel: ObservableObject {
    @Published private(set) var updateStatus: UpdateStatus = .idle

    private let releaseChecker: ReleaseChecking
    private let currentVersion: String
    private var checkTask: Task<Void, Never>?

    init() {
        self.releaseChecker = GitHubReleaseService()
        self.currentVersion = Bundle.main.shortVersionString.normalizedReleaseVersion
    }

    init(
        releaseChecker: ReleaseChecking,
        currentVersion: String
    ) {
        self.releaseChecker = releaseChecker
        self.currentVersion = currentVersion.normalizedReleaseVersion
    }

    deinit {
        checkTask?.cancel()
    }

    func checkForUpdates() {
        guard checkTask == nil else {
            return
        }

        updateStatus = .checking

        checkTask = Task { [weak self, releaseChecker, currentVersion] in
            do {
                let latestRelease = try await releaseChecker.latestRelease()

                await MainActor.run { [weak self] in
                    guard let self, Task.isCancelled == false else {
                        return
                    }

                    if currentVersion.isOlderReleaseVersion(than: latestRelease.version) {
                        updateStatus = .updateAvailable(latestRelease)
                    } else {
                        updateStatus = .current(latestVersion: latestRelease.version)
                    }

                    checkTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, Task.isCancelled == false else {
                        return
                    }

                    updateStatus = .unavailable
                    checkTask = nil
                }
            }
        }
    }
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case current(latestVersion: String)
    case updateAvailable(AppRelease)
    case unavailable
}

private extension Bundle {
    var shortVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
