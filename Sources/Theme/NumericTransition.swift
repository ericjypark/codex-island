import SwiftUI

extension View {
    /// Animated numeric text rolling. macOS 14 introduced
    /// `.contentTransition(.numericText(value:))`; earlier versions get
    /// the basic opacity crossfade so the build still runs on Ventura.
    @ViewBuilder
    func numericTransition(value: Double) -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.numericText(value: value))
        } else {
            self.contentTransition(.opacity)
        }
    }
}
