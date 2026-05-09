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

        Button("Open Codex") {
            viewModel.openCodex()
        }

        Divider()

        pollingRateMenu
        statusBarMenu
        notificationsMenu

        Divider()

        Button("Quit") {
            viewModel.quit()
        }
    }

    private func usageSections(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageSectionView(section: snapshot.fiveHourSection)
            UsageSectionView(section: snapshot.weeklySection)

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
                Button {
                    viewModel.selectPollingInterval(interval)
                } label: {
                    menuRowLabel(title: interval.title, isSelected: viewModel.pollingInterval == interval)
                }
            }
        }
    }

    private var statusBarMenu: some View {
        Menu("Show in Status Bar") {
            ForEach(StatusBarDisplayMode.allCases) { mode in
                Button {
                    viewModel.selectStatusBarDisplayMode(mode)
                } label: {
                    menuRowLabel(title: mode.menuTitle, isSelected: viewModel.statusBarDisplayMode == mode)
                }
            }
        }
    }

    private var notificationsMenu: some View {
        Menu("Notifications") {
            Button {
                viewModel.selectNotificationThreshold(nil)
            } label: {
                menuRowLabel(title: "Off", isSelected: viewModel.notificationThreshold == nil)
            }

            ForEach(NotificationThreshold.allCases) { threshold in
                Button {
                    viewModel.selectNotificationThreshold(threshold)
                } label: {
                    menuRowLabel(title: threshold.title, isSelected: viewModel.notificationThreshold == threshold)
                }
            }
        }
    }

    @ViewBuilder
    private func menuRowLabel(title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct UsageSectionView: View {
    let section: UsageSectionViewData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
