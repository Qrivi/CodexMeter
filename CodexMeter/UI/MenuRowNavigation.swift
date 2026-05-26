import Foundation

enum MenuRowNavigation {
    static func next(after selectedRow: MenuRowID?) -> MenuRowID? {
        let rows = MenuActionCatalog.rows
        guard let selectedRow,
              let index = rows.firstIndex(of: selectedRow) else {
            return rows.first
        }

        let next = rows.index(after: index)
        return next == rows.endIndex ? selectedRow : rows[next]
    }

    static func previous(before selectedRow: MenuRowID?) -> MenuRowID? {
        let rows = MenuActionCatalog.rows
        guard let selectedRow,
              let index = rows.firstIndex(of: selectedRow) else {
            return rows.last
        }

        return index == rows.startIndex ? selectedRow : rows[rows.index(before: index)]
    }
}
