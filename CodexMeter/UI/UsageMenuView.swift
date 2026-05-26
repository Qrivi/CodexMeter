import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            viewModel.menuOpened()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = viewModel.snapshot {
                usageSections(snapshot: snapshot)
            } else if let message = viewModel.currentFailureMessage {
                MessageView(message: message)
            } else {
                MessageView(message: "Loading…")
            }
        }

        Divider()

        statusSection
        actionSection

        Divider()

        settingsSection

        Divider()

        MenuRowButton("Quit", systemImage: "power", role: .destructive) {
            viewModel.quit()
        }
    }

    private func usageSections(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            UsageSectionView(section: snapshot.fiveHourSection)
            Divider()
            UsageSectionView(section: snapshot.weeklySection)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Credits remaining")
                    .font(.headline)
                Text(snapshot.creditsText)
                    .font(.body.monospacedDigit())
            }
        }.padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let snapshot = viewModel.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last updated \(UsageFormatting.lastUpdatedText(from: snapshot.lastUpdated))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let warningMessage = snapshot.warningMessage {
                    Text(warningMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRowButton("Refresh Now", systemImage: "arrow.clockwise") {
                viewModel.refreshNow()
            }

            MenuRowButton("Open Usage Dashboard", systemImage: "chart.bar") {
                viewModel.openUsageDashboard()
            }

            MenuRowButton("Open Codex App", systemImage: "app") {
                viewModel.openCodex()
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingPicker(
                title: "Polling Rate",
                selection: pollingIntervalBinding,
                options: PollingInterval.allCases,
                label: \.title
            )

            settingPicker(
                title: "Show in Menu Bar",
                selection: menuBarDisplayModeBinding,
                options: MenuBarDisplayMode.allCases,
                label: \.menuTitle
            )

            settingPicker(
                title: "Menu Bar Color",
                selection: menuBarColorModeBinding,
                options: MenuBarColorMode.allCases,
                label: \.menuTitle
            )

            settingPicker(
                title: "Low Usage Notification",
                selection: notificationThresholdBinding,
                options: [nil] + NotificationThreshold.allCases.map(Optional.some),
                label: { threshold in threshold?.title ?? "Off" }
            )

            Toggle("Notify when limit resets", isOn: resetNotificationsBinding)
                .toggleStyle(.checkbox)
                .font(.subheadline)
        }
    }

    private func settingPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    private var pollingIntervalBinding: Binding<PollingInterval> {
        Binding(
            get: { viewModel.pollingInterval },
            set: { viewModel.selectPollingInterval($0) }
        )
    }

    private var menuBarDisplayModeBinding: Binding<MenuBarDisplayMode> {
        Binding(
            get: { viewModel.menuBarDisplayMode },
            set: { viewModel.selectMenuBarDisplayMode($0) }
        )
    }

    private var menuBarColorModeBinding: Binding<MenuBarColorMode> {
        Binding(
            get: { viewModel.menuBarColorMode },
            set: { viewModel.selectMenuBarColorMode($0) }
        )
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

private struct MessageView: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

private struct MenuRowButton: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
            .font(.subheadline)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundStyle)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var foregroundStyle: Color {
        if isHovering {
            return .white
        }

        if role == .destructive {
            return .red
        }

        return .primary
    }
}

private struct UsageSectionView: View {
    let section: UsageSectionViewData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.headline)

                Spacer()

                Text(section.remainingText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(color(for: section.level))
            }

            if let remainingPercent = section.remainingPercent {
                ProgressView(value: Double(remainingPercent), total: 100)
                    .tint(color(for: section.level))
            }

            if let resetText = section.resetText {
                Text(resetText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for level: UsageLevel) -> Color {
        switch level {
        case .good:
            .green
        case .warning:
            .yellow
        case .critical:
            .red
        case .neutral:
            .secondary
        }
    }
}
