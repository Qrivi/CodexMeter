import Testing
@testable import CodexMeter

@MainActor
struct MenuRowNavigationTests {
    @Test
    func catalogDefinesRowsInDisplayOrder() {
        #expect(MenuActionCatalog.rows == [.refresh, .dashboard, .codexApp, .settings, .quit])
    }

    @Test
    func onlyRefreshStaysOpenAfterActivation() {
        #expect(MenuActionCatalog.rowsByID[.refresh]?.keepsMenuOpenAfterActivation == true)
        #expect(MenuActionCatalog.rowsByID[.dashboard]?.keepsMenuOpenAfterActivation == false)
        #expect(MenuActionCatalog.rowsByID[.codexApp]?.keepsMenuOpenAfterActivation == false)
        #expect(MenuActionCatalog.rowsByID[.settings]?.keepsMenuOpenAfterActivation == false)
        #expect(MenuActionCatalog.rowsByID[.quit]?.keepsMenuOpenAfterActivation == false)
    }

    @Test
    func startsFromEdgesWhenNothingIsSelected() {
        #expect(MenuRowNavigation.next(after: nil) == .refresh)
        #expect(MenuRowNavigation.previous(before: nil) == .quit)
    }

    @Test
    func movesThroughActionRowsInOrder() {
        #expect(MenuRowNavigation.next(after: .refresh) == .dashboard)
        #expect(MenuRowNavigation.next(after: .dashboard) == .codexApp)
        #expect(MenuRowNavigation.next(after: .codexApp) == .settings)
        #expect(MenuRowNavigation.next(after: .settings) == .quit)

        #expect(MenuRowNavigation.previous(before: .quit) == .settings)
        #expect(MenuRowNavigation.previous(before: .settings) == .codexApp)
        #expect(MenuRowNavigation.previous(before: .codexApp) == .dashboard)
        #expect(MenuRowNavigation.previous(before: .dashboard) == .refresh)
    }

    @Test
    func staysAtEdges() {
        #expect(MenuRowNavigation.next(after: .quit) == .quit)
        #expect(MenuRowNavigation.previous(before: .refresh) == .refresh)
    }
}
