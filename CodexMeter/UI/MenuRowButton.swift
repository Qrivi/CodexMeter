import SwiftUI

struct MenuRowSection<Content: View>: View {
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

struct MenuRowButton: View {
    let action: MenuActionDescriptor
    @Binding var selectedRow: MenuRowID?
    @Binding var hoveredRow: MenuRowID?
    let isEnabled: Bool
    let perform: () -> Void

    init(
        _ action: MenuActionDescriptor,
        selectedRow: Binding<MenuRowID?>,
        hoveredRow: Binding<MenuRowID?>,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) {
        self.action = action
        self._selectedRow = selectedRow
        self._hoveredRow = hoveredRow
        self.isEnabled = isEnabled
        self.perform = perform
    }

    var body: some View {
        Button {
            selectedRow = action.id
            perform()
        } label: {
            HStack(alignment: .center, spacing: 6) {
                if let icon = action.icon {
                    actionIcon(icon)
                        .frame(width: 16, alignment: .center)
                        .padding(.leading, 2)
                }

                Text(action.title)

                Spacer()

                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .foregroundStyle(shortcutForegroundStyle)
                }
            }
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .focusable(false)
        .foregroundStyle(foregroundStyle)
        .opacity(isEnabled ? 1 : 0.45)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: MacOSRelease.isSequoia ? 5 : 8)
                    .fill(Color.accentColor)
            }
        }
        .onHover { isHovering in
            if isHovering {
                hoveredRow = action.id
                selectedRow = nil
            } else if hoveredRow == action.id {
                hoveredRow = nil
            }
        }
    }

    private var isHighlighted: Bool {
        guard isEnabled else {
            return false
        }

        if let selectedRow {
            return selectedRow == action.id
        }

        return hoveredRow == action.id
    }

    @ViewBuilder
    private func actionIcon(_ icon: MenuActionIcon) -> some View {
        let size: CGFloat = MacOSRelease.isSequoia ? 15 : 13;
        
        switch icon {
        case .system(let systemImage):
            Image(systemName: systemImage)
                .font(.body)
                .imageScale(MacOSRelease.isSequoia ? .medium : .small)
        case .asset(let assetImage):
            Image(assetImage)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }

    private var foregroundStyle: AnyShapeStyle {
        guard isEnabled else {
            return AnyShapeStyle(.secondary)
        }

        if isHighlighted {
            return AnyShapeStyle(.white)
        }

        return AnyShapeStyle(.primary)
    }

    private var shortcutForegroundStyle: AnyShapeStyle {
        guard isEnabled else {
            return AnyShapeStyle(.tertiary)
        }

        if isHighlighted {
            return AnyShapeStyle(.white)
        }

        return AnyShapeStyle(.tertiary)
    }
}

#if DEBUG
private struct MenuRowButtonPreview: View {
    @State private var selectedRow: MenuRowID? = .settings
    @State private var hoveredRow: MenuRowID?

    var body: some View {
        MenuRowSection {
            MenuRowButton(
                MenuActionCatalog.rowsByID[.settings]!,
                selectedRow: $selectedRow,
                hoveredRow: $hoveredRow,
                perform: {}
            )

            MenuRowButton(
                MenuActionCatalog.rowsByID[.refresh]!,
                selectedRow: $selectedRow,
                hoveredRow: $hoveredRow,
                isEnabled: false,
                perform: {}
            )
        }
        .padding(6)
        .frame(width: 340)
    }
}

struct MenuRowButton_Previews: PreviewProvider {
    static var previews: some View {
        MenuRowButtonPreview()
            .previewDisplayName("Menu Row Button")
    }
}
#endif
