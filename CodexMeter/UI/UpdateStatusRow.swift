import SwiftUI

struct UpdateStatusRow: View {
    let status: AppUpdateStatus
    let canCheckForUpdates: Bool
    let checkForUpdates: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusLabel
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(buttonTitle, action: checkForUpdates)
                .buttonStyle(.bordered)
                .disabled(!canCheckForUpdates)
                .fixedSize()
        }
    }

    private var buttonTitle: String {
        if case .available = status { return "Update Now" }
        return "Check for Updates"
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .unavailable:
            Label("Updates unavailable in this build.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .notChecked:
            Label("Update status not checked.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .checking:
            Label("Checking for updates…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .current:
            Label("You are on the latest release.", systemImage: "checkmark.circle")
                .foregroundStyle(UsageStatusPalette.good)
        case let .available(version):
            Label("Version \(version) available.", systemImage: "arrow.down.circle")
                .foregroundStyle(UsageStatusPalette.warning)
        case .noUpdateAvailable:
            Label("No update available.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .failed:
            Label("Could not check for updates.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}
