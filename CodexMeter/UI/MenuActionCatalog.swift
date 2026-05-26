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
    let icon: MenuActionIcon?
    let shortcut: String?
    let keepsMenuOpenAfterActivation: Bool

    init(
        id: MenuRowID,
        title: String,
        systemImage: String?,
        shortcut: String? = nil,
        keepsMenuOpenAfterActivation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = systemImage.map(MenuActionIcon.system)
        self.shortcut = shortcut
        self.keepsMenuOpenAfterActivation = keepsMenuOpenAfterActivation
    }

    init(
        id: MenuRowID,
        title: String,
        assetImage: String?,
        shortcut: String? = nil,
        keepsMenuOpenAfterActivation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = assetImage.map(MenuActionIcon.asset)
        self.shortcut = shortcut
        self.keepsMenuOpenAfterActivation = keepsMenuOpenAfterActivation
    }
}

enum MenuActionIcon: Equatable {
    case system(String)
    case asset(String)
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
        MenuActionDescriptor(id: .codexApp, title: "Open Codex App", assetImage: "CodexLogo")
    ]

    static let appActions = appActions(on: ProcessInfo.processInfo.operatingSystemVersion)

    static let rows = usageActions.map(\.id) + appActions.map(\.id)
    static let rowsByID = Dictionary(uniqueKeysWithValues: (usageActions + appActions).map { ($0.id, $0) })

    static func appActions(on version: OperatingSystemVersion) -> [MenuActionDescriptor] {
        [
            MenuActionDescriptor(id: .settings, title: "Settings", systemImage: MacOSRelease.isSequoia(version) ? nil : "gear", shortcut: "⌘ ,"),
            MenuActionDescriptor(id: .quit, title: "Quit CodexMeter", systemImage: MacOSRelease.isSequoia(version) ? nil : "xmark.rectangle", shortcut: "⌘ Q")
        ]
    }
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
