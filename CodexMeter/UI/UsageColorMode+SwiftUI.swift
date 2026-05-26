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

            return UsageStatusPalette.critical
        }
    }

    private func color(for level: UsageLevel) -> Color {
        UsageStatusPalette.color(for: level)
    }
}
