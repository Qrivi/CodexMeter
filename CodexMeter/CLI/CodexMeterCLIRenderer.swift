import Foundation

struct CodexMeterCLIRenderer: Sendable {
    private let width: Int
    private let usesANSI: Bool

    nonisolated init(width: Int = 48, usesANSI: Bool) {
        self.width = max(width, 8)
        self.usesANSI = usesANSI
    }

    nonisolated func render(meters: [UsageMeterViewData]) -> String {
        meters
            .map(renderMeter)
            .joined(separator: "\n\n")
    }

    private nonisolated func renderMeter(_ meter: UsageMeterViewData) -> String {
        let valueText = colorValue(meter.valueText, meter: meter)
        var lines = [
            alignedLine(left: meter.title, right: valueText, rawRight: meter.valueText)
        ]

        if meter.kind == .rateLimit, let remainingPercent = meter.remainingPercent {
            lines.append(progressBar(remainingPercent: remainingPercent, level: meter.level))
        }

        if let resetText = meter.resetText {
            lines.append(dim(resetText))
        }

        return lines.joined(separator: "\n")
    }

    private nonisolated func alignedLine(left: String, right: String, rawRight: String) -> String {
        let spaces = max(1, width - left.count - rawRight.count)
        return left + String(repeating: " ", count: spaces) + right
    }

    private nonisolated func progressBar(remainingPercent: Int, level: UsageLevel) -> String {
        let clampedPercent = max(0, min(100, remainingPercent))
        let filledCount = Int((Double(clampedPercent) / 100 * Double(width)).rounded())
        let emptyCount = max(0, width - filledCount)
        let filledText = String(repeating: "█", count: filledCount)
        let emptyText = String(repeating: "█", count: emptyCount)

        guard usesANSI else {
            return filledText + String(repeating: "░", count: emptyCount)
        }

        return ANSI.color(for: level) + filledText + ANSI.reset + dim(emptyText)
    }

    private nonisolated func colorValue(_ text: String, meter: UsageMeterViewData) -> String {
        guard usesANSI,
              meter.kind == .rateLimit,
              let remainingPercent = meter.remainingPercent,
              remainingPercent <= NotificationThreshold.twenty.rawValue else {
            return text
        }

        return ANSI.color(for: meter.level) + text + ANSI.reset
    }

    private nonisolated func dim(_ text: String) -> String {
        guard usesANSI, text.isEmpty == false else {
            return text
        }

        return ANSI.dim + text + ANSI.reset
    }
}

private enum ANSI {
    static let reset = "\u{001B}[0m"
    static let dim = "\u{001B}[2m"
    static let good = "\u{001B}[38;2;107;189;148m"
    static let warning = "\u{001B}[38;2;209;158;61m"
    static let critical = "\u{001B}[38;2;224;122;122m"

    nonisolated static func color(for level: UsageLevel) -> String {
        switch level {
        case .good:
            good
        case .warning:
            warning
        case .critical:
            critical
        case .neutral:
            reset
        }
    }
}
