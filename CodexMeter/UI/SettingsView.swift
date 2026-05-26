import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        Form {
            Section("Menu Bar") {
                settingPicker(
                    title: "Show in Menu Bar",
                    selection: menuBarDisplayModeBinding,
                    options: MenuBarDisplayMode.allCases,
                    label: \.menuTitle
                )

                settingPicker(
                    title: "Menu Bar Color",
                    selection: menuBarColorModeBinding,
                    options: MenuBarColorMode.allCases,
                    label: \.menuTitle
                )
            }

            Section("Updates & Notifications") {
                settingPicker(
                    title: "Polling Rate",
                    selection: pollingIntervalBinding,
                    options: PollingInterval.allCases,
                    label: \.title
                )

                settingPicker(
                    title: "Low Usage Notification",
                    selection: notificationThresholdBinding,
                    options: [nil] + NotificationThreshold.allCases.map(Optional.some),
                    label: { threshold in threshold?.title ?? "Off" }
                )

                Toggle("Notify when limit resets", isOn: resetNotificationsBinding)
                    .toggleStyle(.checkbox)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }

    private func settingPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option))
                    .tag(option)
            }
        }
        .pickerStyle(.menu)
    }

    private var pollingIntervalBinding: Binding<PollingInterval> {
        Binding(
            get: { viewModel.pollingInterval },
            set: { viewModel.selectPollingInterval($0) }
        )
    }

    private var menuBarDisplayModeBinding: Binding<MenuBarDisplayMode> {
        Binding(
            get: { viewModel.menuBarDisplayMode },
            set: { viewModel.selectMenuBarDisplayMode($0) }
        )
    }

    private var menuBarColorModeBinding: Binding<MenuBarColorMode> {
        Binding(
            get: { viewModel.menuBarColorMode },
            set: { viewModel.selectMenuBarColorMode($0) }
        )
    }

    private var notificationThresholdBinding: Binding<NotificationThreshold?> {
        Binding(
            get: { viewModel.limitNotificationThreshold },
            set: { viewModel.selectNotificationThreshold($0) }
        )
    }

    private var resetNotificationsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.resetNotificationsEnabled },
            set: { viewModel.setResetNotificationsEnabled($0) }
        )
    }
}
