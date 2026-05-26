import SwiftUI

struct SettingsView: View {
    private let preferredWidth: CGFloat = 720
    private let preferredHeight: CGFloat = 480

    @ObservedObject var viewModel: UsageViewModel
    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                Text("CodexMeter")
                    .font(.title)
                    .padding(16)

                List(SettingsPane.allCases, selection: $selection) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            selectedPaneView
                .navigationTitle(selection.title)
        }
        .frame(
            minWidth: preferredWidth,
            idealWidth: preferredWidth,
            maxWidth: preferredWidth,
            minHeight: preferredHeight,
            idealHeight: preferredHeight,
            maxHeight: .infinity
        )
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

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: PreviewSupport.viewModel())
            .previewDisplayName("Settings Window")
    }
}
#endif
