import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var isMenuBarDark = true

    var body: some View {
        let title = viewModel.menuBarTitle
        let segments = viewModel.menuBarTextSegments

        ZStack {
            MenuBarAppearanceReader(isDark: $isMenuBarDark)
                .frame(width: 0, height: 0)

            Image(nsImage: MenuBarLabelImage.make(title: title, segments: segments, isMenuBarDark: isMenuBarDark))
                .id(labelIdentity(title: title, segments: segments, isMenuBarDark: isMenuBarDark))
        }
    }

    private func labelIdentity(title: String, segments: [MenuBarLabelSegment], isMenuBarDark: Bool) -> String {
        let segmentIdentity = segments
            .map { "\($0.text):\($0.tone)" }
            .joined(separator: "|")

        return "\(title)|\(segmentIdentity)|\(isMenuBarDark)"
    }
}

private struct MenuBarAppearanceReader: NSViewRepresentable {
    @Binding var isDark: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isDark: $isDark)
    }

    func makeNSView(context: Context) -> AppearanceView {
        let view = AppearanceView()
        view.onAppearanceChange = context.coordinator.updateAppearance
        return view
    }

    func updateNSView(_ nsView: AppearanceView, context: Context) {
        context.coordinator.isDark = $isDark
        nsView.onAppearanceChange = context.coordinator.updateAppearance
    }

    final class AppearanceView: NSView {
        var onAppearanceChange: ((Bool) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportAppearance()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            reportAppearance()
        }

        func reportAppearance() {
            let appearance = window?.effectiveAppearance ?? effectiveAppearance
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            onAppearanceChange?(match == .darkAqua)
        }
    }

    final class Coordinator {
        var isDark: Binding<Bool>

        init(isDark: Binding<Bool>) {
            self.isDark = isDark
        }

        func updateAppearance(_ newValue: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isDark.wrappedValue != newValue else {
                    return
                }

                self.isDark.wrappedValue = newValue
            }
        }
    }
}

private enum MenuBarLabelImage {
    private static let height: CGFloat = 22
    private static let labelFont = NSFont.systemFont(ofSize: 7, weight: .regular)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    static func make(title: String, segments: [MenuBarLabelSegment], isMenuBarDark: Bool) -> NSImage {
        let titleSize = title.size(withAttributes: [.font: labelFont])
        let segmentWidths = segments.map { $0.text.size(withAttributes: [.font: valueFont]).width }
        let valueWidth = segmentWidths.reduce(0, +)
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
                .foregroundColor: MenuBarLabelColors.labelColor(isMenuBarDark: isMenuBarDark)
            ]
        )
        var x: CGFloat = 0
        for (segment, segmentWidth) in zip(segments, segmentWidths) {
            segment.text.draw(
                at: NSPoint(x: x, y: 0),
                withAttributes: [
                    .font: valueFont,
                    .foregroundColor: MenuBarLabelColors.color(for: segment.tone, isMenuBarDark: isMenuBarDark)
                ]
            )
            x += segmentWidth
        }

        image.isTemplate = false
        return image
    }
}

enum MenuBarLabelColors {
    static func labelColor(isMenuBarDark: Bool) -> NSColor {
        isMenuBarDark ? .white : .black
    }

    static func color(for tone: MenuBarTextTone, isMenuBarDark: Bool) -> NSColor {
        switch tone {
        case .neutral:
            labelColor(isMenuBarDark: isMenuBarDark)
        case .good, .warning, .critical:
            UsageStatusPalette.color(for: tone)
        }
    }
}

#if DEBUG
struct MenuBarStatusLabel_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarStatusLabel(viewModel: PreviewSupport.viewModel())
            .padding()
            .previewDisplayName("Menu Bar Status Label")
    }
}
#endif
