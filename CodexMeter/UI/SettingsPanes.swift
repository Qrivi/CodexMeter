import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        SettingsPaneContainer {
            Section("Startup") {
                SettingsToggleRow(
                    title: "Launch at login",
                    description: "Start CodexMeter automatically when you sign in.",
                    isOn: launchAtLoginBinding
                )

                if let message = viewModel.settingsErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(UsageStatusPalette.critical)
                }
            }

            Section("Updates") {
                SettingsPickerRow(
                    title: "Polling rate",
                    description: "Choose how often CodexMeter refreshes usage in the background.",
                    selection: pollingIntervalBinding,
                    options: PollingInterval.allCases,
                    label: \.title
                )

                SettingsToggleRow(
                    title: "Poll when menu opens",
                    description: "Refresh immediately when opening the menu bar window (useful when background polling rate is low).",
                    isOn: pollOnMenuOpenBinding
                )
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLoginEnabled },
            set: { viewModel.setLaunchAtLoginEnabled($0) }
        )
    }

    private var pollingIntervalBinding: Binding<PollingInterval> {
        Binding(
            get: { viewModel.pollingInterval },
            set: { viewModel.selectPollingInterval($0) }
        )
    }

    private var pollOnMenuOpenBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pollOnMenuOpen },
            set: { viewModel.setPollOnMenuOpen($0) }
        )
    }
}

struct AppearanceSettingsPane: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        SettingsPaneContainer {
            Section("Menu Bar") {
                SettingsPickerRow(
                    title: "Usage shown in menu bar",
                    description: "Choose which usage value is always visible next to the menu bar title.",
                    selection: menuBarDisplayModeBinding,
                    options: MenuBarDisplayMode.allCases,
                    label: \.menuTitle
                )

                SettingsPickerRow(
                    title: "Menu bar colors",
                    description: "Control how the compact menu bar numbers use warning colors.",
                    selection: menuBarColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle
                )
            }

            Section("In-App Meters") {
                SettingsPickerRow(
                    title: "Meter colors",
                    description: "Choose how the progress meters inside the menu window are tinted.",
                    selection: meterColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle
                )

                SettingsPickerRow(
                    title: "Remaining label colors",
                    description: "Choose how the remaining percentage labels above each meter are colored.",
                    selection: remainingLabelColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle
                )
            }
        }
    }

    private var menuBarDisplayModeBinding: Binding<MenuBarDisplayMode> {
        Binding(
            get: { viewModel.menuBarDisplayMode },
            set: { viewModel.selectMenuBarDisplayMode($0) }
        )
    }

    private var menuBarColorModeBinding: Binding<UsageColorMode> {
        Binding(
            get: { viewModel.menuBarColorMode },
            set: { viewModel.selectMenuBarColorMode($0) }
        )
    }

    private var meterColorModeBinding: Binding<UsageColorMode> {
        Binding(
            get: { viewModel.meterColorMode },
            set: { viewModel.selectMeterColorMode($0) }
        )
    }

    private var remainingLabelColorModeBinding: Binding<UsageColorMode> {
        Binding(
            get: { viewModel.remainingLabelColorMode },
            set: { viewModel.selectRemainingLabelColorMode($0) }
        )
    }
}

struct NotificationSettingsPane: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        SettingsPaneContainer {
            Section("Usage Limits") {
                SettingsPickerRow(
                    title: "Low usage notification",
                    description: "Send a notification when either usage window falls below the selected remaining percentage.",
                    selection: notificationThresholdBinding,
                    options: [nil] + NotificationThreshold.allCases.map(Optional.some),
                    label: { threshold in threshold?.title ?? "Off" }
                )

                SettingsToggleRow(
                    title: "Notify when limit resets",
                    description: "Send a notification after a usage window returns to a full allowance.",
                    isOn: resetNotificationsBinding
                )
            }
        }
    }

    private var notificationThresholdBinding: Binding<NotificationThreshold?> {
        Binding(
            get: { viewModel.limitNotificationThreshold },
            set: { viewModel.selectNotificationThreshold($0) }
        )
    }

    private var resetNotificationsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.resetNotificationsEnabled },
            set: { viewModel.setResetNotificationsEnabled($0) }
        )
    }
}

struct AboutSettingsPane: View {
    @StateObject private var model = AboutPaneModel()

    var body: some View {
        SettingsPaneContainer {
            Section("CodexMeter") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Image("CodexLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 42, height: 42)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("CodexMeter")
                                .font(.title2.weight(.semibold))

                            Text(versionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Small menu bar app for monitoring Codex usage limits.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    updateStatusView
                    
                    Divider()

                    Text("Install with Homebrew for the simplest updates:")
                        .foregroundStyle(.secondary)

                    Text("brew install qrivi/tap/codexmeter")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Text("Then update with:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("brew upgrade codexmeter")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }

            Section("Privacy") {
                privacyText
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }

            Section("Links") {
                VStack(alignment: .leading, spacing: 8) {
                    Link(destination: Self.repositoryURL) {
                        Label("GitHub repository", systemImage: "arrow.up.right.square")
                    }

                    Link(destination: Self.releasesURL) {
                        Label("Releases", systemImage: "shippingbox")
                    }

                    Link(destination: Self.licenseURL) {
                        Label("MIT License", systemImage: "doc.text")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .task {
            model.checkForUpdates()
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (version?, build?):
            return "Version \(version) (\(build))"
        case let (version?, nil):
            return "Version \(version)"
        default:
            return "Version unavailable"
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch model.updateStatus {
        case .idle, .checking:
            Label("Checking GitHub for updates...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)

        case let .current(latestVersion):
            Label("You are on the latest release, \(latestVersion).", systemImage: "checkmark.circle")
                .foregroundStyle(UsageStatusPalette.good)

        case let .updateAvailable(release):
            VStack(alignment: .leading, spacing: 8) {
                Label("Update available: \(release.version)", systemImage: "arrow.down.circle")
                    .foregroundStyle(UsageStatusPalette.warning)

                Link(destination: release.pageURL) {
                    Label("Open latest release", systemImage: "arrow.up.right.square")
                }
            }

        case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                Label("Could not check for updates right now.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)

                Button("Check Again") {
                    model.checkForUpdates()
                }
            }
        }
    }

    private var privacyText: Text {
        Text("CodexMeter reads your local Codex auth session from ")
            + Text("~/.codex/auth.json")
                .font(.system(.body, design: .monospaced))
            + Text(" to fetch usage information. It does not ask for or store your password.")
    }

    private static let repositoryURL = URL(string: "https://github.com/Qrivi/CodexMeter")!
    private static let releasesURL = URL(string: "https://github.com/Qrivi/CodexMeter/releases")!
    private static let licenseURL = URL(string: "https://github.com/Qrivi/CodexMeter/blob/main/LICENSE")!
}

#if DEBUG
struct SettingsPanes_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            GeneralSettingsPane(viewModel: PreviewSupport.viewModel())
                .frame(width: 520, height: 360)
                .previewDisplayName("General Settings")

            AppearanceSettingsPane(viewModel: PreviewSupport.viewModel())
                .frame(width: 520, height: 520)
                .previewDisplayName("Appearance Settings")

            NotificationSettingsPane(viewModel: PreviewSupport.viewModel())
                .frame(width: 520, height: 280)
                .previewDisplayName("Notification Settings")

            AboutSettingsPane()
                .frame(width: 520, height: 280)
                .previewDisplayName("About Settings")
        }
    }
}
#endif
