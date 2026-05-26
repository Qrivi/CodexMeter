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
                        .foregroundStyle(.red)
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
                    description: "Refresh immediately when opening the menu bar window, useful when the background polling rate is low.",
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
                ) {
                    MenuBarColorPreview(colorMode: viewModel.menuBarColorMode)
                }
            }

            Section("In-App Meters") {
                SettingsPickerRow(
                    title: "Meter colors",
                    description: "Choose how the progress meters inside the menu window are tinted.",
                    selection: meterColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle
                ) {
                    MeterColorPreview(colorMode: viewModel.meterColorMode)
                }

                SettingsPickerRow(
                    title: "Remaining label colors",
                    description: "Choose how the remaining percentage labels above each meter are colored.",
                    selection: remainingLabelColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle
                ) {
                    RemainingLabelColorPreview(colorMode: viewModel.remainingLabelColorMode)
                }
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
    var body: some View {
        SettingsPaneContainer {
            Section("CodexMeter") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CodexMeter")
                        .font(.title2.weight(.semibold))

                    Text("A small macOS menu bar app for keeping an eye on Codex usage limits.")
                        .foregroundStyle(.secondary)

                    Text(versionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Privacy") {
                Text("CodexMeter reads the Codex auth file from ~/.codex/auth.json. It does not ask for or store your password.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
