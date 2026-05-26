import SwiftUI

extension UsageColorMode {
    func color(level: UsageLevel, remainingPercent: Int?) -> Color {
        switch self {
        case .monochrome:
            return .secondary
        case .colorful:
            return color(for: level)
        case .colorfulWhenLow:
            guard let remainingPercent,
                  remainingPercent <= NotificationThreshold.twenty.rawValue else {
                return .secondary
            }

            return .red
        }
    }

    private func color(for level: UsageLevel) -> Color {
        switch level {
        case .good:
            .green
        case .warning:
            .yellow
        case .critical:
            .red
        case .neutral:
            .secondary
        }
    }
}
