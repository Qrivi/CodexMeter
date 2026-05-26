import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
        } detail: {
            selectedPaneView
        }
    }

    @ViewBuilder
    private var selectedPaneView: some View {
        switch selection {
        case .general:
            GeneralSettingsPane(viewModel: viewModel)
        case .appearance:
            AppearanceSettingsPane(viewModel: viewModel)
        case .notifications:
            NotificationSettingsPane(viewModel: viewModel)
        case .about:
            AboutSettingsPane()
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case notifications
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        case .notifications:
            "Notifications"
        case .about:
            "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .appearance:
            "paintpalette"
        case .notifications:
            "bell"
        case .about:
            "info.circle"
        }
    }
}
