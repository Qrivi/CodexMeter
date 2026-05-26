import Foundation

enum MenuRowID: Hashable {
    case refresh
    case dashboard
    case codexApp
    case settings
    case quit
}

struct MenuActionDescriptor: Identifiable, Equatable {
    let id: MenuRowID
    let title: String
    let systemImage: String
    let shortcut: String?
    let keepsMenuOpenAfterActivation: Bool

    init(
        id: MenuRowID,
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        keepsMenuOpenAfterActivation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.keepsMenuOpenAfterActivation = keepsMenuOpenAfterActivation
    }
}

enum MenuActionCatalog {
    static let usageActions = [
        MenuActionDescriptor(
            id: .refresh,
            title: "Refresh Now",
            systemImage: "arrow.clockwise",
            keepsMenuOpenAfterActivation: true
        ),
        MenuActionDescriptor(id: .dashboard, title: "Open Usage Dashboard", systemImage: "chart.bar"),
        MenuActionDescriptor(id: .codexApp, title: "Open Codex App", systemImage: "app")
    ]

    static let appActions = [
        MenuActionDescriptor(id: .settings, title: "Settings", systemImage: "gearshape", shortcut: "⌘ ,"),
        MenuActionDescriptor(id: .quit, title: "Quit", systemImage: "power", shortcut: "⌘ Q")
    ]

    static let rows = usageActions.map(\.id) + appActions.map(\.id)
    static let rowsByID = Dictionary(uniqueKeysWithValues: (usageActions + appActions).map { ($0.id, $0) })
}

enum MenuActionSection {
    case usage
    case app

    var actions: [MenuActionDescriptor] {
        switch self {
        case .usage:
            MenuActionCatalog.usageActions
        case .app:
            MenuActionCatalog.appActions
        }
    }
}
