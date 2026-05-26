import AppKit
import SwiftUI

enum UsageStatusPalette {
    static let good = Color(nsColor: goodColor)
    static let warning = Color(nsColor: warningColor)
    static let critical = Color(nsColor: criticalColor)

    static let goodColor = NSColor(calibratedRed: 0.42, green: 0.74, blue: 0.58, alpha: 1)
    static let warningColor = NSColor(calibratedRed: 0.82, green: 0.62, blue: 0.24, alpha: 1)
    static let criticalColor = NSColor(calibratedRed: 0.88, green: 0.48, blue: 0.48, alpha: 1)

    static func color(for level: UsageLevel) -> Color {
        switch level {
        case .good:
            good
        case .warning:
            warning
        case .critical:
            critical
        case .neutral:
            .secondary
        }
    }

    static func color(for tone: MenuBarTextTone) -> NSColor {
        switch tone {
        case .neutral:
            .textColor
        case .good:
            goodColor
        case .warning:
            warningColor
        case .critical:
            criticalColor
        }
    }
}
