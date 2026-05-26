import SwiftUI

struct MenuBarColorPreview: View {
    let colorMode: UsageColorMode

    var body: some View {
        HStack(spacing: 4) {
            Text("Limits")
                .foregroundStyle(.secondary)

            Text("64%")
                .foregroundStyle(colorMode.color(level: .good, remainingPercent: 64))

            Text("/")
                .foregroundStyle(.secondary)

            Text("18%")
                .foregroundStyle(colorMode.color(level: .critical, remainingPercent: 18))
        }
        .font(.caption.monospacedDigit())
        .padding(.leading, 2)
    }
}

struct MeterColorPreview: View {
    let colorMode: UsageColorMode

    var body: some View {
        VStack(spacing: 6) {
            previewMeter(value: 64, level: .good)
            previewMeter(value: 18, level: .critical)
        }
        .frame(maxWidth: 240)
    }

    private func previewMeter(value: Int, level: UsageLevel) -> some View {
        ProgressView(value: Double(value), total: 100)
            .tint(colorMode.color(level: level, remainingPercent: value))
    }
}

struct RemainingLabelColorPreview: View {
    let colorMode: UsageColorMode

    var body: some View {
        HStack(spacing: 12) {
            Text("64% remaining")
                .foregroundStyle(colorMode.color(level: .good, remainingPercent: 64))

            Text("18% remaining")
                .foregroundStyle(colorMode.color(level: .critical, remainingPercent: 18))
        }
        .font(.caption.monospacedDigit())
        .padding(.leading, 2)
    }
}
