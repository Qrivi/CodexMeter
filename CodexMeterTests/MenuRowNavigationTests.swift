import Foundation
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
    func hidesSettingsAndQuitIconsOnSequoia() throws {
        let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 2)
        let appActions = Dictionary(uniqueKeysWithValues: MenuActionCatalog.appActions(on: sequoia).map { ($0.id, $0) })

        #expect(try #require(MenuActionCatalog.rowsByID[.refresh]).icon != nil)
        #expect(try #require(MenuActionCatalog.rowsByID[.dashboard]).icon != nil)
        #expect(try #require(MenuActionCatalog.rowsByID[.codexApp]).icon != nil)
        #expect(try #require(appActions[.settings]).icon == nil)
        #expect(try #require(appActions[.quit]).icon == nil)
    }

    @Test
    func keepsSettingsAndQuitIconsOnNonSequoiaReleases() throws {
        let tahoe = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        let appActions = Dictionary(uniqueKeysWithValues: MenuActionCatalog.appActions(on: tahoe).map { ($0.id, $0) })

        #expect(try #require(appActions[.settings]).icon != nil)
        #expect(try #require(appActions[.quit]).icon != nil)
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
