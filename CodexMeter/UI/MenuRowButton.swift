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
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.body)
                    .frame(width: 16, alignment: .center)
                    .padding(.leading, 2)

                Text(action.title)

                Spacer()

                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .foregroundStyle(shortcutForegroundStyle)
                }
            }
            .font(.body)
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .focusable(false)
        .foregroundStyle(foregroundStyle)
        .opacity(isEnabled ? 1 : 0.45)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 5)
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

    private var foregroundStyle: Color {
        guard isEnabled else {
            return .secondary
        }

        if isHighlighted {
            return .white
        }

        return .primary
    }

    private var shortcutForegroundStyle: Color {
        guard isEnabled else {
            return .secondary
        }

        if isHighlighted {
            return .white
        }

        return .secondary
    }
}
