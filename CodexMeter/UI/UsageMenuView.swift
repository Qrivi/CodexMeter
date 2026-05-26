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
        
        actionSection

        Divider()

        appSection
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

    private var actionSection: some View {
        MenuRowSection {
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

    private var appSection: some View {
        MenuRowSection {
            MenuRowButton("Settings", systemImage: "gearshape", shortcut: "⌘,") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }

            MenuRowButton("Quit", systemImage: "power", shortcut: "⌘Q") {
                viewModel.quit()
            }
        }
    }
}

private struct MenuRowSection<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content()
        }
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

private struct MenuRowButton: View {
    let title: String
    let systemImage: String
    let shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 16, alignment: .center)

                Text(title)

                Spacer(minLength: 0)

                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(shortcutForegroundStyle)
                }
            }
            .font(.body)
            .padding(horizontal: 6, vertical: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(foregroundStyle)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor)
            }
        }
        .onHover { isHovering = $0 }
    }

    private var foregroundStyle: Color {
        if isHovering {
            return .white
        }

        return .primary
    }

    private var shortcutForegroundStyle: Color {
        if isHovering {
            return .white
        }

        return .secondary
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
