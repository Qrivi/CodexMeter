import SwiftUI

struct UsageMenuActionsView: View {
    let isRefreshEnabled: Bool
    let refresh: () -> Void
    let openUsageDashboard: () -> Void
    let openCodex: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var receivesKeyboardInput: Bool
    @State private var selectedRow: MenuRowID?
    @State private var hoveredRow: MenuRowID?

    var body: some View {
        VStack(alignment: .leading) {
            actionSection

            Divider()
                .padding(.horizontal, 11)

            appSection
        }
        .onAppear {
            selectedRow = nil
            hoveredRow = nil
            receivesKeyboardInput = true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($receivesKeyboardInput)
        .onMoveCommand(perform: moveSelection)
        .onKeyPress(.return, action: activateSelectedRow)
        .onKeyPress(.space, action: activateSelectedRow)
    }

    private var actionSection: some View {
        menuSection(.usage)
    }

    private var appSection: some View {
        menuSection(.app)
    }

    private func menuSection(_ section: MenuActionSection) -> some View {
        MenuRowSection {
            ForEach(section.actions) { action in
                MenuRowButton(
                    action,
                    selectedRow: $selectedRow,
                    hoveredRow: $hoveredRow,
                    isEnabled: isActionEnabled(action.id)
                ) {
                    perform(action.id)
                }
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
        guard isActionEnabled(row) else {
            return
        }

        defer {
            if shouldHideMenu(afterActivating: row) {
                dismiss()
            }
        }

        switch row {
        case .refresh:
            refresh()
        case .dashboard:
            openUsageDashboard()
        case .codexApp:
            openCodex()
        case .settings:
            openSettings()
        case .quit:
            quit()
        }
    }

    private func shouldHideMenu(afterActivating row: MenuRowID) -> Bool {
        MenuActionCatalog.rowsByID[row]?.keepsMenuOpenAfterActivation != true
    }

    private func isActionEnabled(_ row: MenuRowID) -> Bool {
        switch row {
        case .refresh:
            isRefreshEnabled
        default:
            true
        }
    }
}

#if DEBUG
struct UsageMenuActionsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UsageMenuActionsView(
                isRefreshEnabled: true,
                refresh: {},
                openUsageDashboard: {},
                openCodex: {},
                openSettings: {},
                quit: {}
            )
            .padding(6)
            .frame(width: 340)
            .previewDisplayName("Usage Menu Actions")

            UsageMenuActionsView(
                isRefreshEnabled: false,
                refresh: {},
                openUsageDashboard: {},
                openCodex: {},
                openSettings: {},
                quit: {}
            )
            .padding(6)
            .frame(width: 340)
            .previewDisplayName("Usage Menu Actions Disabled Refresh")
        }
    }
}
#endif
