import AppKit
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openSettings) private var openSettings
    @FocusState private var receivesKeyboardInput: Bool
    @State private var selectedRow: MenuRowID?
    @State private var hoveredRow: MenuRowID?

    var body: some View {
        VStack(alignment: .leading) {
            content
        }
        .padding(6)
        .frame(width: 340)
        .onAppear {
            selectedRow = nil
            hoveredRow = nil
            viewModel.menuOpened()
            receivesKeyboardInput = true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($receivesKeyboardInput)
        .onMoveCommand(perform: moveSelection)
        .onKeyPress(.return, action: activateSelectedRow)
        .onKeyPress(.space, action: activateSelectedRow)
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
            MenuRowButton(
                .refresh,
                "Refresh Now",
                systemImage: "arrow.clockwise",
                selectedRow: $selectedRow,
                hoveredRow: $hoveredRow
            ) {
                perform(.refresh)
            }

            MenuRowButton(
                .dashboard,
                "Open Usage Dashboard",
                systemImage: "chart.bar",
                selectedRow: $selectedRow,
                hoveredRow: $hoveredRow
            ) {
                perform(.dashboard)
            }

            MenuRowButton(
                .codexApp,
                "Open Codex App",
                systemImage: "app",
                selectedRow: $selectedRow,
                hoveredRow: $hoveredRow
            ) {
                perform(.codexApp)
            }
        }
    }

    private var appSection: some View {
        MenuRowSection {
            MenuRowButton(
                .settings,
                "Settings",
                systemImage: "gearshape",
                shortcut: "⌘,",
                selectedRow: $selectedRow,
                hoveredRow: $hoveredRow
            ) {
                perform(.settings)
            }

            MenuRowButton(
                .quit,
                "Quit",
                systemImage: "power",
                shortcut: "⌘Q",
                selectedRow: $selectedRow,
                hoveredRow: $hoveredRow
            ) {
                perform(.quit)
            }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        switch direction {
        case .down:
            selectNextRow()
        case .up:
            selectPreviousRow()
        default:
            break
        }
    }

    private func selectNextRow() {
        let currentRow = selectedRow ?? hoveredRow
        hoveredRow = nil
        selectedRow = MenuRowNavigation.next(after: currentRow)
    }

    private func selectPreviousRow() {
        let currentRow = selectedRow ?? hoveredRow
        hoveredRow = nil
        selectedRow = MenuRowNavigation.previous(before: currentRow)
    }

    private func activateSelectedRow() -> KeyPress.Result {
        guard let selectedRow else {
            return .ignored
        }

        perform(selectedRow)
        return .handled
    }

    private func perform(_ row: MenuRowID) {
        switch row {
        case .refresh:
            viewModel.refreshNow()
        case .dashboard:
            viewModel.openUsageDashboard()
        case .codexApp:
            viewModel.openCodex()
        case .settings:
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        case .quit:
            viewModel.quit()
        }
    }
}

enum MenuRowID: CaseIterable {
    case refresh
    case dashboard
    case codexApp
    case settings
    case quit
}

enum MenuRowNavigation {
    static func next(after selectedRow: MenuRowID?) -> MenuRowID? {
        let rows = MenuRowID.allCases
        guard let selectedRow,
              let index = rows.firstIndex(of: selectedRow) else {
            return rows.first
        }

        let next = rows.index(after: index)
        return next == rows.endIndex ? selectedRow : rows[next]
    }

    static func previous(before selectedRow: MenuRowID?) -> MenuRowID? {
        let rows = MenuRowID.allCases
        guard let selectedRow,
              let index = rows.firstIndex(of: selectedRow) else {
            return rows.last
        }

        return index == rows.startIndex ? selectedRow : rows[rows.index(before: index)]
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
    let row: MenuRowID
    let title: String
    let systemImage: String
    let shortcut: String?
    @Binding var selectedRow: MenuRowID?
    @Binding var hoveredRow: MenuRowID?
    let action: () -> Void

    init(
        _ row: MenuRowID,
        _ title: String,
        systemImage: String,
        shortcut: String? = nil,
        selectedRow: Binding<MenuRowID?>,
        hoveredRow: Binding<MenuRowID?>,
        action: @escaping () -> Void
    ) {
        self.row = row
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self._selectedRow = selectedRow
        self._hoveredRow = hoveredRow
        self.action = action
    }

    var body: some View {
        Button {
            selectedRow = row
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
            if isHighlighted {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor)
            }
        }
        .onHover { isHovering in
            if isHovering {
                hoveredRow = row
                selectedRow = nil
            } else if hoveredRow == row {
                hoveredRow = nil
            }
        }
    }

    private var isHighlighted: Bool {
        if let selectedRow {
            return selectedRow == row
        }

        return hoveredRow == row
    }

    private var foregroundStyle: Color {
        if isHighlighted {
            return .white
        }

        return .primary
    }

    private var shortcutForegroundStyle: Color {
        if isHighlighted {
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
