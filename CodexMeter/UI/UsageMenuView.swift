import AppKit
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading) {
            content
        }
        .padding(6)
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

        statusSection

        Divider()

        UsageMenuActionsView(
            refresh: viewModel.refreshNow,
            openUsageDashboard: viewModel.openUsageDashboard,
            openCodex: viewModel.openCodex,
            openSettings: openSettingsWindow,
            quit: viewModel.quit
        )
    }

    private func usageSections(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            UsageSectionView(section: snapshot.fiveHourSection)
            UsageSectionView(section: snapshot.weeklySection)
            HStack(alignment: .firstTextBaseline) {
                Text("Credits remaining")
                    .font(.headline)
                Spacer()
                Text(snapshot.creditsText)
                    .font(.body.monospacedDigit())
            }
        }
        .padding(10)
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
            }.padding(.horizontal, 10)
        }
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MessageView: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
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
