import SwiftUI

struct SettingsView: View {
    private let preferredWidth: CGFloat = 660
    private let preferredHeight: CGFloat = 420
    private let preferredSidebarWidth: CGFloat = 180

    @ObservedObject var viewModel: UsageViewModel
    @State private var selection: SettingsPane = .general
    @State private var showsAppearancePreview = false

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
            .navigationSplitViewColumnWidth(min: preferredSidebarWidth - 25, ideal: preferredSidebarWidth, max: preferredSidebarWidth + 25)
        } detail: {
            selectedPaneView
                .navigationTitle(selection.title)
                .toolbar {
                    if selection == .appearance {
                        ToolbarItem(placement: .primaryAction) {
                            let title = showsAppearancePreview ? "Hide Preview" : "Show Preview"

                            Button {
                                withAnimation(.snappy) {
                                    showsAppearancePreview.toggle()
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: showsAppearancePreview ? "eye.slash" : "eye")
                                        .font(.body)
                                        .frame(height: 16)

                                    Text(title)
                                        .font(.caption2)
                                        .frame(width: 72)
                                }
                                .frame(width: 76, height: 34)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(title)
                            .padding(.horizontal, 10)
                        }
                    }
                }
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
            VStack(spacing: 0) {
                if showsAppearancePreview {
                    AppearanceSettingsPreview(
                        menuBarDisplayMode: viewModel.menuBarDisplayMode,
                        menuBarColorMode: viewModel.menuBarColorMode,
                        meterColorMode: viewModel.meterColorMode,
                        remainingLabelColorMode: viewModel.remainingLabelColorMode
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                AppearanceSettingsPane(viewModel: viewModel)
            }
            .animation(.snappy, value: showsAppearancePreview)
        case .meters:
            MeterSettingsPane(viewModel: viewModel)
        case .about:
            AboutSettingsPane()
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case meters
    case appearance
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        case .meters:
            "Meters"
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
        case .meters:
            "gauge.with.dots.needle.50percent"
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
