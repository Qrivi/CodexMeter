import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var viewModel: UsageViewModel

    init() {
        let preferencesStore = PreferencesStore()
        let viewModel = UsageViewModel(
            usageService: UsageService(tokenProvider: AuthTokenProvider()),
            preferencesStore: preferencesStore,
            appLauncher: AppLauncher(),
            notificationService: NotificationService()
        )
        viewModel.start()
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(viewModel: viewModel)
        } label: {
            Image(nsImage: StatusBarLabelImage.make(title: viewModel.statusBarTitle, value: viewModel.statusBarText))
        }
        .menuBarExtraStyle(.menu)
    }
}

private enum StatusBarLabelImage {
    private static let height: CGFloat = 22
    private static let labelFont = NSFont.systemFont(ofSize: 7, weight: .regular)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    static func make(title: String, value: String) -> NSImage {
        let titleSize = title.size(withAttributes: [.font: labelFont])
        let valueSize = value.size(withAttributes: [.font: valueFont])
        let width = max(titleSize.width, valueSize.width)
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        title.draw(
            at: NSPoint(x: 0, y: 12),
            withAttributes: [
                .font: labelFont,
                .foregroundColor: NSColor.labelColor
            ]
        )
        value.draw(
            at: NSPoint(x: 0, y: 0),
            withAttributes: [
                .font: valueFont,
                .foregroundColor: NSColor.textColor
            ]
        )

        image.isTemplate = false
        return image
    }
}
