import Foundation

enum UsageLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(message: String)
}

enum UsageLevel: String, Equatable, Sendable {
    case good
    case warning
    case critical
    case neutral
}

enum MenuBarTextTone: Equatable, Sendable {
    case neutral
    case good
    case warning
    case critical
}

struct MenuBarLabelSegment: Equatable, Sendable {
    let text: String
    let tone: MenuBarTextTone
}
