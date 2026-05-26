import SwiftUI

extension View {
    func padding(horizontal: CGFloat, vertical: CGFloat) -> some View {
        self.padding(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
    }
}
