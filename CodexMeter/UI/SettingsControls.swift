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
    let preview: () -> Preview

    init(
        title: String,
        description: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String,
        @ViewBuilder preview: @escaping () -> Preview
    ) {
        self.title = title
        self.description = description
        self.selection = selection
        self.options = options
        self.label = label
        self.preview = preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Picker(title, selection: selection) {
                    ForEach(options, id: \.self) { option in
                        Text(label(option))
                            .tag(option)
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
        label: @escaping (Value) -> String
    ) {
        self.init(
            title: title,
            description: description,
            selection: selection,
            options: options,
            label: label,
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
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
