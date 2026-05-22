import AppKit
import SwiftUI

@main
struct CodexMeterApp: App {
    @StateObject private var viewModel: UsageViewModel

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)

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
            MenuBarStatusLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        let title = viewModel.menuBarTitle
        let segments = viewModel.menuBarTextSegments

        Image(nsImage: MenuBarLabelImage.make(title: title, segments: segments))
            .id(labelIdentity(title: title, segments: segments))
    }

    private func labelIdentity(title: String, segments: [MenuBarLabelSegment]) -> String {
        let segmentIdentity = segments
            .map { "\($0.text):\($0.tone)" }
            .joined(separator: "|")

        return "\(title)|\(segmentIdentity)"
    }
}

private enum MenuBarLabelImage {
    private static let height: CGFloat = 22
    private static let labelFont = NSFont.systemFont(ofSize: 7, weight: .regular)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    static func make(title: String, segments: [MenuBarLabelSegment]) -> NSImage {
        let titleSize = title.size(withAttributes: [.font: labelFont])
        let valueWidth = segments.reduce(0) { width, segment in
            width + segment.text.size(withAttributes: [.font: valueFont]).width
        }
        let width = max(titleSize.width, valueWidth)
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
        var x: CGFloat = 0
        for segment in segments {
            segment.text.draw(
                at: NSPoint(x: x, y: 0),
                withAttributes: [
                    .font: valueFont,
                    .foregroundColor: color(for: segment.tone)
                ]
            )
            x += segment.text.size(withAttributes: [.font: valueFont]).width
        }

        image.isTemplate = false
        return image
    }

    private static func color(for tone: MenuBarTextTone) -> NSColor {
        switch tone {
        case .neutral:
            return .textColor
        case .good:
            return .systemGreen
        case .warning:
            return .systemYellow
        case .critical:
            return .systemRed
        }
    }
}
