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
                    options: viewModel.menuBarDisplayOptions,
                    label: { viewModel.menuBarDisplayTitle(for: $0) },
                    isEnabled: { viewModel.isMenuBarDisplayModeEnabled($0) },
                    showsDividerBefore: { viewModel.menuBarDisplayDividerOptions.contains($0) }
                )

                SettingsPickerRow(
                    title: "Menu bar colors",
                    description: "Control how the compact menu bar numbers use warning colors.",
                    selection: menuBarColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle,
                    showsDividerBefore: { $0 == .colorful }
                )
            }

            Section("In-App Meters") {
                SettingsPickerRow(
                    title: "Meter colors",
                    description: "Choose how the progress meters inside the menu window are tinted.",
                    selection: meterColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle,
                    showsDividerBefore: { $0 == .colorful }
                )

                SettingsPickerRow(
                    title: "Remaining label colors",
                    description: "Choose how the remaining percentage labels above each meter are colored.",
                    selection: remainingLabelColorModeBinding,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle,
                    showsDividerBefore: { $0 == .colorful }
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

struct MeterSettingsPane: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        SettingsPaneContainer {
            if let snapshot = viewModel.snapshot {
                Section("Plan limits") {
                    ForEach(snapshot.mainRateLimitMeters) { meter in
                        meterSettingsBlock(for: meter)
                    }
                }

                if snapshot.additionalRateLimitMeters.isEmpty == false {
                    Section("Additional Rate Limits") {
                        ForEach(snapshot.additionalRateLimitMeters) { meter in
                            meterSettingsBlock(for: meter)
                        }
                    }
                }

                Section("Credits and resets") {
                    if let creditsMeter = snapshot.creditsMeter {
                        meterSettingsBlock(for: creditsMeter)
                    }

                    if let resetsMeter = snapshot.usageLimitResetsMeter {
                        meterSettingsBlock(for: resetsMeter)
                    }
                }
            } else {
                Section {
                    Text("Usage meters will appear after CodexMeter loads your usage.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func meterSettingsBlock(for meter: UsageMeterViewData) -> some View {
        let isVisible = viewModel.preferences(for: meter.id).isVisible

        VStack(alignment: .leading, spacing: 12) {
            Text(meter.title)
                .font(.headline)

            SettingsToggleRow(
                title: "Show meter",
                description: "Show or hide this meter in the menu bar app.",
                isOn: visibilityBinding(for: meter.id)
            )
            .disabled(meter.isAvailable == false)

            if meter.isAvailable == false {
                Label("This usage meter is currently not available.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isVisible {
                notificationSettings(for: meter)
                    .transition(meterDetailsTransition)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func notificationSettings(for meter: UsageMeterViewData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch meter.kind {
            case .rateLimit:
                SettingsPickerRow(
                    title: "Low usage notification",
                    description: "Notify when the remaining percentage is reached.",
                    selection: notificationThresholdBinding(for: meter.id),
                    options: [nil] + NotificationThreshold.allCases.map(Optional.some),
                    label: { $0?.title ?? "Off" },
                    showsDividerBefore: { $0 == .some(.twenty) }
                )
                SettingsToggleRow(
                    title: "Limit reset notification",
                    description: "Notify after this meter returns to a full allowance.",
                    isOn: resetNotificationsBinding(for: meter.id)
                )
            case .credits:
                if meter.supportsNotifications {
                    SettingsPickerRow(
                        title: "Low credits notification",
                        description: "Notify at or below this credit balance.",
                        selection: Binding(
                            get: { viewModel.preferences(for: .credits).creditsNotificationThreshold },
                            set: { viewModel.selectCreditsNotificationThreshold($0) }
                        ),
                        options: [nil] + CreditsNotificationThreshold.allCases.map(Optional.some),
                        label: { $0?.title ?? "Off" },
                        showsDividerBefore: { $0 == .some(.twoHundredFifty) }
                    )
                    SettingsToggleRow(
                        title: "Credits added notification",
                        description: "Notify when credits are added.",
                        isOn: notificationBinding(for: meter.id, preference: \.creditsAddedNotificationsEnabled)
                    )
                } else {
                    Label("Notifications require a numeric credit balance.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .usageLimitResets:
                SettingsToggleRow(
                    title: "Reset used notification",
                    description: "Notify when a reset is used or expires.",
                    isOn: notificationBinding(for: meter.id, preference: \.resetsUsedNotificationsEnabled)
                )
                SettingsToggleRow(
                    title: "Reset added notification",
                    description: "Notify when resets are added.",
                    isOn: notificationBinding(for: meter.id, preference: \.resetsAddedNotificationsEnabled)
                )
            }
        }
    }

    private func notificationBinding(
        for meterID: UsageMeterID,
        preference: WritableKeyPath<MeterPreferences, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { viewModel.preferences(for: meterID)[keyPath: preference] },
            set: { viewModel.setNotificationEnabled($0, meterID: meterID, preference: preference) }
        )
    }

    private var meterDetailsTransition: AnyTransition {
        accessibilityReduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: -8))
    }

    private var meterDetailsAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.12)
            : .snappy(duration: 0.25)
    }

    private func visibilityBinding(for meterID: UsageMeterID) -> Binding<Bool> {
        Binding(
            get: { viewModel.preferences(for: meterID).isVisible },
            set: { isVisible in
                withAnimation(meterDetailsAnimation) {
                    viewModel.setMeterVisible(isVisible, meterID: meterID)
                }
            }
        )
    }

    private func notificationThresholdBinding(for meterID: UsageMeterID) -> Binding<NotificationThreshold?> {
        Binding(
            get: { viewModel.preferences(for: meterID).notificationThreshold },
            set: { viewModel.selectNotificationThreshold($0, meterID: meterID) }
        )
    }

    private func resetNotificationsBinding(for meterID: UsageMeterID) -> Binding<Bool> {
        Binding(
            get: { viewModel.preferences(for: meterID).resetNotificationsEnabled },
            set: { viewModel.setResetNotificationsEnabled($0, meterID: meterID) }
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

            MeterSettingsPane(viewModel: PreviewSupport.viewModel())
                .frame(width: 520, height: 280)
                .previewDisplayName("Meter Settings")

            AboutSettingsPane()
                .frame(width: 520, height: 280)
                .previewDisplayName("About Settings")
        }
    }
}
#endif
