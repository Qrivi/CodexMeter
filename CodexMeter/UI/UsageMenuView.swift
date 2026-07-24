import AppKit
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading) {
            content
        }
        .padding(MacOSRelease.isSequoia ? 4 : 6)
        .frame(width: 280)
        .onAppear {
            viewModel.menuOpened()
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = viewModel.snapshot {
                usageSections(snapshot: snapshot)
            } else if let message = viewModel.currentFailureMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                Text("Loading…")
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }

        statusSection

        Divider()
            .padding(.horizontal, 11)

        TimelineView(.periodic(from: Date(), by: 1)) { context in
            UsageMenuActionsView(
                isRefreshEnabled: viewModel.canRefreshNow(at: context.date),
                refresh: viewModel.refreshNow,
                openUsageDashboard: viewModel.openUsageDashboard,
                openCodex: viewModel.openCodex,
                openSettings: openSettingsWindow,
                quit: viewModel.quit
            )
        }
    }

    private func usageSections(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            let visibleMeters = viewModel.visibleMeters(in: snapshot)

            if visibleMeters.isEmpty {
                Text("No meters are enabled. You can enable meters in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(visibleMeters) { meter in
                    UsageSectionView(
                        meter: meter,
                        meterColorMode: viewModel.meterColorMode,
                        remainingLabelColorMode: viewModel.remainingLabelColorMode
                    )
                }
            }
        }
        .padding(.horizontal, MacOSRelease.isSequoia ? 10 : 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusSection: some View {
        if let snapshot = viewModel.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last updated \(UsageFormatting.lastUpdatedText(from: snapshot.lastUpdated))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let warningMessage = snapshot.warningMessage {
                    Text(warningMessage)
                        .font(.footnote)
                        .foregroundStyle(UsageStatusPalette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, MacOSRelease.isSequoia ? 10 : 12)
        }
    }

    private func openSettingsWindow() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct UsageSectionView: View {
    let meter: UsageMeterViewData
    let meterColorMode: UsageColorMode
    let remainingLabelColorMode: UsageColorMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(meter.title)
                    .font(.headline)

                Spacer()

                Text(meter.valueText)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(remainingLabelColorMode.color(
                        level: meter.level,
                        remainingPercent: meter.remainingPercent
                    ))
            }

            if let remainingPercent = meter.remainingPercent {
                UsageMeterView(
                    remainingPercent: remainingPercent,
                    color: meterColorMode.color(level: meter.level, remainingPercent: remainingPercent)
                )
            }

            if let resetText = meter.resetText {
                Text(resetText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct UsageMeterView: View {
    let remainingPercent: Int
    let color: Color

    private var fillFraction: CGFloat {
        CGFloat(min(max(remainingPercent, 0), 100)) / 100
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.55))

                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * fillFraction)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining usage")
        .accessibilityValue("\(min(max(remainingPercent, 0), 100)) percent")
    }
}

#if DEBUG
struct UsageMenuView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UsageMenuView(viewModel: PreviewSupport.viewModel())
                .frame(width: 340)
                .previewDisplayName("Usage Menu")

            UsageMenuView(viewModel: PreviewSupport.failingViewModel())
                .frame(width: 340)
                .previewDisplayName("Usage Menu Error")

            UsageSectionView(
                meter: PreviewSupport.snapshot.meter(id: .secondary)!,
                meterColorMode: .colorful,
                remainingLabelColorMode: .colorfulWhenLow
            )
            .padding()
            .frame(width: 340)
            .previewDisplayName("Usage Section")
        }
    }
}
#endif
