import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingWithoutSnapshot {
                Text("Loading…")
            } else {
                content
            }
        }
        .frame(minWidth: 320)
        .onAppear {
            viewModel.menuOpened()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = viewModel.snapshot {
            usageSections(snapshot: snapshot)
        } else if let message = viewModel.currentFailureMessage {
            Text(message)
                .foregroundStyle(.secondary)
        } else {
            Text("Loading…")
        }

        Divider()

        if let snapshot = viewModel.snapshot {
            if let authGuidanceMessage = snapshot.authGuidanceMessage {
                Text(authGuidanceMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let warningMessage = snapshot.warningMessage {
                Text(warningMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("Last updated \(UsageFormatting.lastUpdatedText(from: snapshot.lastUpdated))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        Button("Refresh Now") {
            viewModel.refreshNow()
        }

        Button("Open Usage Dashboard") {
            viewModel.openUsageDashboard()
        }

        Button("Open Codex App") {
            viewModel.openCodex()
        }

        Divider()

        pollingRateMenu
        menuBarMenu
        notificationsMenu

        Divider()

        Button("Quit") {
            viewModel.quit()
        }
    }

    private func usageSections(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageSectionView(section: snapshot.fiveHourSection)
            Divider()
            UsageSectionView(section: snapshot.weeklySection)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Credits remaining")
                    .font(.headline)
                Text(snapshot.creditsText)
            }
        }
    }

    private var pollingRateMenu: some View {
        Menu("Polling Rate") {
            ForEach(PollingInterval.allCases) { interval in
                selectionToggle(
                    interval.title,
                    isSelected: viewModel.pollingInterval == interval,
                    select: { viewModel.selectPollingInterval(interval) }
                )
            }
        }
    }

    private var menuBarMenu: some View {
        Menu("Show in Menu Bar") {
            Text("Usage Data")

            ForEach(MenuBarDisplayMode.allCases) { mode in
                selectionToggle(
                    mode.menuTitle,
                    isSelected: viewModel.menuBarDisplayMode == mode,
                    select: { viewModel.selectMenuBarDisplayMode(mode) }
                )
            }

            Divider()
            Text("Color")

            ForEach(MenuBarColorMode.allCases) { mode in
                selectionToggle(
                    mode.menuTitle,
                    isSelected: viewModel.menuBarColorMode == mode,
                    select: { viewModel.selectMenuBarColorMode(mode) }
                )
            }
        }
    }

    private var notificationsMenu: some View {
        Menu("Notifications") {
            Text("Low Usage")

            selectionToggle(
                "Off",
                isSelected: viewModel.limitNotificationThreshold == nil,
                select: { viewModel.selectNotificationThreshold(nil) }
            )

            ForEach(NotificationThreshold.allCases) { threshold in
                selectionToggle(
                    threshold.title,
                    isSelected: viewModel.limitNotificationThreshold == threshold,
                    select: { viewModel.selectNotificationThreshold(threshold) }
                )
            }

            Divider()
            Text("Limit Reset")

            selectionToggle(
                "Off",
                isSelected: viewModel.resetNotificationsEnabled == false,
                select: { viewModel.setResetNotificationsEnabled(false) }
            )

            selectionToggle(
                "Notify when reset",
                isSelected: viewModel.resetNotificationsEnabled,
                select: { viewModel.setResetNotificationsEnabled(true) }
            )
        }
    }

    private func selectionToggle(
        _ title: String,
        isSelected: Bool,
        select: @escaping () -> Void
    ) -> some View {
        Toggle(
            "  \(title)",
            isOn: selectionBinding(isSelected: isSelected, select: select)
        )
    }

    private func selectionBinding(isSelected: Bool, select: @escaping () -> Void) -> Binding<Bool> {
        Binding(
            get: { isSelected },
            set: { newValue in
                if newValue {
                    select()
                }
            }
        )
    }
}

private struct UsageSectionView: View {
    let section: UsageSectionViewData

    var body: some View {
        VStack(alignment: .leading) {
            Text(section.title)
                .font(.headline)

            Text(section.remainingText)
                .foregroundStyle(color(for: section.level))

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
