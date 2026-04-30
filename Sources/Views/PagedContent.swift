import SwiftUI

/// Two-page horizontal carousel: the usage data row (page 0) and the cost
/// data row (page 1). Both pages render at the full content width; the
/// HStack is twice that width and slides via `.offset` based on
/// `ScreenPref.screen`. Animation uses the same spring as the expanded-
/// state shape morph for cohesion.
///
/// Only the data row swipes — `PanelHeader` and `PanelFooter` are mounted
/// outside this view so they stay fixed across page changes.
///
/// First-encounter peek: on every expand until the user has swiped at
/// least once (`ScreenPref.hasSwipedScreen`), the data row slides ~28pt
/// left to reveal the cost screen's edge, then settles back. Subtle and
/// time-bounded so it stops nagging once they've discovered the gesture.
struct PagedContent: View {
    @ObservedObject private var screenPref = ScreenPref.shared
    @State private var peekOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let pageWidth = geo.size.width
            HStack(spacing: 0) {
                UsageView()
                    .frame(width: pageWidth)
                CostView()
                    .frame(width: pageWidth)
            }
            .frame(width: pageWidth, alignment: .leading)
            .offset(x: (screenPref.screen == .usage ? 0 : -pageWidth) + peekOffset)
            .animation(.openMorph, value: screenPref.screen)
            .clipped()
            .onAppear {
                guard !reduceMotion,
                      !screenPref.hasSwipedScreen,
                      screenPref.screen == .usage
                else { return }
                schedulePeek()
            }
            .onChange(of: screenPref.hasSwipedScreen) { swiped in
                // User swiped mid-peek: collapse the peek smoothly so the
                // composite offset doesn't jump when the real screen
                // transition fires alongside it.
                if swiped, peekOffset != 0 {
                    withAnimation(.easeOut(duration: 0.25)) { peekOffset = 0 }
                }
            }
        }
    }

    private func schedulePeek() {
        // 0.30s wait lets the open-morph spring settle before the peek
        // starts — peeking during the initial expand would feel chaotic.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            guard !screenPref.hasSwipedScreen else { return }
            withAnimation(.easeOut(duration: 0.50)) { peekOffset = -28 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                guard !screenPref.hasSwipedScreen else { return }
                withAnimation(.easeIn(duration: 0.40)) { peekOffset = 0 }
            }
        }
    }
}
