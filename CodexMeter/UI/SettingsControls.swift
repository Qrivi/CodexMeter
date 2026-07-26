import SwiftUI

struct SettingsPaneContainer<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct SettingsPickerRow<Value: Hashable, Preview: View>: View {
    let title: String
    let description: String
    let selection: Binding<Value>
    let options: [Value]
    let label: (Value) -> String
    let isEnabled: (Value) -> Bool
    let showsDividerBefore: (Value) -> Bool
    let preview: () -> Preview

    init(
        title: String,
        description: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String,
        isEnabled: @escaping (Value) -> Bool = { _ in true },
        showsDividerBefore: @escaping (Value) -> Bool = { _ in false },
        @ViewBuilder preview: @escaping () -> Preview
    ) {
        self.title = title
        self.description = description
        self.selection = selection
        self.options = options
        self.label = label
        self.isEnabled = isEnabled
        self.showsDividerBefore = showsDividerBefore
        self.preview = preview
    }

    private var optionSections: [[Value]] {
        options.reduce(into: []) { sections, option in
            if sections.isEmpty || showsDividerBefore(option) {
                sections.append([])
            }
            sections[sections.index(before: sections.endIndex)].append(option)
        }
    }

    private var validatedSelection: Binding<Value> {
        Binding(
            get: { selection.wrappedValue },
            set: { newValue in
                guard isEnabled(newValue) else {
                    return
                }
                selection.wrappedValue = newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Picker(title, selection: validatedSelection) {
                    ForEach(Array(optionSections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section, id: \.self) { option in
                                Text(label(option))
                                    .tag(option)
                                    .selectionDisabled(isEnabled(option) == false)
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } label: {
                SettingsRowLabel(title: title, description: description)
            }

            preview()
        }
    }
}

extension SettingsPickerRow where Preview == EmptyView {
    init(
        title: String,
        description: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String,
        isEnabled: @escaping (Value) -> Bool = { _ in true },
        showsDividerBefore: @escaping (Value) -> Bool = { _ in false }
    ) {
        self.init(
            title: title,
            description: description,
            selection: selection,
            options: options,
            label: label,
            isEnabled: isEnabled,
            showsDividerBefore: showsDividerBefore,
            preview: { EmptyView() }
        )
    }
}

struct SettingsToggleRow: View {
    let title: String
    let description: String
    let isOn: Binding<Bool>

    var body: some View {
        LabeledContent {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        } label: {
            SettingsRowLabel(title: title, description: description)
        }
    }
}

private struct SettingsRowLabel: View {
    private let descriptionMaxWidth: CGFloat = 270

    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: descriptionMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
private struct SettingsControlsPreview: View {
    @State private var colorMode: UsageColorMode = .colorfulWhenLow
    @State private var isEnabled = true

    var body: some View {
        SettingsPaneContainer {
            Section("Picker") {
                SettingsPickerRow(
                    title: "Menu bar colors",
                    description: "Control how compact menu bar numbers use warning colors.",
                    selection: $colorMode,
                    options: UsageColorMode.allCases,
                    label: \.menuTitle
                )
            }

            Section("Toggle") {
                SettingsToggleRow(
                    title: "Poll when menu opens",
                    description: "Refresh immediately when opening the menu bar window.",
                    isOn: $isEnabled
                )
            }
        }
        .frame(width: 520, height: 320)
    }
}

struct SettingsControls_Previews: PreviewProvider {
    static var previews: some View {
        SettingsControlsPreview()
            .previewDisplayName("Settings Controls")
    }
}
#endif
