import SwiftUI

struct AppearanceSettingsPreview: View {
    private let cycleDuration: TimeInterval = 15

    let menuBarDisplayMode: MenuBarDisplayMode
    let menuBarColorMode: UsageColorMode
    let meterColorMode: UsageColorMode
    let remainingLabelColorMode: UsageColorMode

    var body: some View {
        TimelineView(.animation) { context in
            let remainingPercent = animatedPercent(at: context.date)
            let level = UsageFormatting.level(for: remainingPercent)
            let snapshot = previewSnapshot(remainingPercent: remainingPercent, level: level)

            VStack(alignment: .leading, spacing: 8) {
                menuBarPreview(snapshot: snapshot)
                HStack {
                    Spacer()
                    appMenuPreview(remainingPercent: remainingPercent, level: level)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func menuBarPreview(snapshot: UsageSnapshot) -> some View {
        let segments = UsageFormatting.menuBarLabelSegments(
            snapshot: snapshot,
            mode: menuBarDisplayMode,
            colorMode: menuBarColorMode,
            state: .loaded
        )

        return HStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.body)
                Text("Finder")
                    .fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Text("View")
                Text("Window")
                Text("Help")
            }
            .font(.caption)
            .foregroundStyle(.primary)

            Spacer(minLength: 12)

            MenuBarItemPreview(
                title: UsageFormatting.menuBarTitle(
                    snapshot: snapshot,
                    mode: menuBarDisplayMode
                ),
                segments: segments
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary)
        }
    }

    private func appMenuPreview(remainingPercent: Int, level: UsageLevel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("5 hour limit")
                    .font(.headline)

                Spacer()

                Text("\(remainingPercent)% remaining")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(remainingLabelColorMode.color(
                        level: level,
                        remainingPercent: remainingPercent
                    ))
            }

            ProgressView(value: Double(remainingPercent), total: 100)
                .tint(meterColorMode.color(level: level, remainingPercent: remainingPercent))
        }
        .padding(.horizontal, MacOSRelease.isSequoia ? 10 : 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }

    private func animatedPercent(at date: Date) -> Int {
        let cyclePosition = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration * 2)
        let progress = cyclePosition <= cycleDuration
            ? cyclePosition / cycleDuration
            : (cycleDuration * 2 - cyclePosition) / cycleDuration

        return Int((progress * 100).rounded())
    }

    private func previewSnapshot(remainingPercent: Int, level: UsageLevel) -> UsageSnapshot {
        let weeklyPercent = 100 - remainingPercent

        return UsageSnapshot(
            meters: [previewMeter(
                id: .primary,
                title: "5 hour limit",
                remainingPercent: remainingPercent,
                level: level
            ),
            previewMeter(
                id: .secondary,
                title: "Weekly limit",
                remainingPercent: weeklyPercent,
                level: UsageFormatting.level(for: weeklyPercent)
            ),
            UsageMeterViewData(
                id: .credits,
                kind: .credits,
                title: "Credits remaining",
                valueText: "1,234",
                resetText: nil,
                remainingPercent: nil,
                level: .neutral,
                resetDate: nil,
                isAvailable: true
            )],
            lastUpdated: Date(),
            warningMessage: nil
        )
    }

    private func previewMeter(
        id: UsageMeterID,
        title: String,
        remainingPercent: Int,
        level: UsageLevel
    ) -> UsageMeterViewData {
        UsageMeterViewData(
            id: id,
            kind: .rateLimit,
            title: title,
            valueText: "\(remainingPercent)% remaining",
            resetText: nil,
            remainingPercent: remainingPercent,
            level: level,
            resetDate: nil,
            isAvailable: true,
            compactTitle: title
                .replacingOccurrences(of: " limit", with: "")
        )
    }
}

private struct MenuBarItemPreview: View {
    let title: String
    let segments: [MenuBarLabelSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 7))
                .lineLimit(1)

            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Text(segment.text)
                        .foregroundStyle(color(for: segment.tone))
                }
            }
            .font(.system(size: 12).monospacedDigit())
            .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    private func color(for tone: MenuBarTextTone) -> Color {
        switch tone {
        case .neutral:
            .primary
        case .good:
            UsageStatusPalette.good
        case .warning:
            UsageStatusPalette.warning
        case .critical:
            UsageStatusPalette.critical
        }
    }
}

#if DEBUG
struct SettingsPreviewComponents_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AppearanceSettingsPreview(
                menuBarDisplayMode: .primaryRemaining,
                menuBarColorMode: .colorfulWhenLow,
                meterColorMode: .colorful,
                remainingLabelColorMode: .colorfulWhenLow
            )
            .padding()
            .previewDisplayName("Appearance Settings Preview")

            AppearanceSettingsPreview(
                menuBarDisplayMode: .both,
                menuBarColorMode: .colorful,
                meterColorMode: .monochrome,
                remainingLabelColorMode: .colorful
            )
            .padding()
            .previewDisplayName("Appearance Settings Preview Both")
        }
    }
}
#endif
