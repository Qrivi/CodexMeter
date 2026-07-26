import Combine
import Foundation

@MainActor
final class CLISettingsModel: ObservableObject {
    @Published private(set) var installLocation: CLIInstallLocation
    @Published private(set) var installStatus: CLIInstallStatus
    @Published private(set) var errorMessage: String?

    private let preferencesStore: PreferencesStore
    private let installService: CLIInstallService

    convenience init() {
        self.init(
            preferencesStore: PreferencesStore(),
            installService: CLIInstallService()
        )
    }

    init(
        preferencesStore: PreferencesStore,
        installService: CLIInstallService
    ) {
        let location = CLIInstallLocation(path: preferencesStore.cliInstallPath)
        self.preferencesStore = preferencesStore
        self.installService = installService
        self.installLocation = location
        self.installStatus = installService.status(for: location)
    }

    func selectInstallLocation(_ location: CLIInstallLocation) {
        installLocation = location
        preferencesStore.cliInstallPath = location.path
        errorMessage = nil
        refresh()
    }

    func install() {
        errorMessage = nil

        do {
            try installService.install(in: installLocation)
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }

    func remove() {
        errorMessage = nil

        do {
            try installService.remove(from: installLocation)
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }

    func refresh() {
        installStatus = installService.status(for: installLocation)
    }

    var manualInstallCommand: String {
        installService.manualInstallCommand(for: installLocation)
    }
}
