import SwiftUI

/// Two-dot page indicator that mirrors the active screen. Sits in the
/// expanded panel footer between the style chip and the live-status group.
struct PageIndicator: View {
    let active: ScreenPref.Screen

    var body: some View {
        HStack(spacing: 5) {
            dot(active: active == .usage)
            dot(active: active == .cost)
        }
        .animation(.strongEaseOut, value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page indicator")
        .accessibilityValue(active == .usage ? "Usage page, 1 of 2" : "Cost page, 2 of 2")
    }

    private func dot(active: Bool) -> some View {
        Circle()
            .fill(.white.opacity(active ? 0.78 : 0.22))
            .frame(width: 5, height: 5)
    }
}
