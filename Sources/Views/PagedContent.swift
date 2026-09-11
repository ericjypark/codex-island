import SwiftUI

/// Three-page horizontal carousel: live usage (page 0), cost (page 1), and
/// history overview (page 2). Each page renders at the full content width;
/// the layout slides based on
/// `ScreenPref.screen`. Horizontal movement gets its own drawer-style curve
/// so page navigation does not inherit the island shape's spring bounce.
///
/// Only the data row swipes — `PanelHeader` and `PanelFooter` are mounted
/// outside this view so they stay fixed across page changes.
///
/// First-encounter peek: on every expand until the user has swiped at
/// least once (`ScreenPref.hasSwipedScreen`), the data row slides ~28pt
/// left to reveal the cost screen's edge, then settles back. Subtle and
/// time-bounded so it stops nagging once they've discovered the gesture.
struct PagedContent: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var screenPref = ScreenPref.shared
    @State private var peekOffset: CGFloat = 0
    @State private var bumpOffset: CGFloat = 0

    var body: some View {
        ContentSizedPageLayout(selectedPage: screenPref.screen.pageIndex,
                               position: CGFloat(screenPref.screen.pageIndex),
                               feedbackOffset: peekOffset + bumpOffset) {
            UsageView()
                .padding(.vertical, 24)
                .accessibilityHidden(screenPref.screen != .usage)
            CostView()
                .padding(.vertical, 24)
                .accessibilityHidden(screenPref.screen != .cost)
            OverviewView()
                .accessibilityHidden(screenPref.screen != .overview)
        }
        .clipped()
        .onAppear {
            // Discoverability cue, not decorative motion — fires even
            // when @Environment(\.accessibilityReduceMotion) is on,
            // because without it reduce-motion users have no path to
            // learn the second screen exists. The motion is brief
            // (~1s total) and slow-eased.
            guard !screenPref.hasSwipedScreen,
                  screenPref.screen == .usage
            else { return }
            schedulePeek()
        }
        .onChange(of: screenPref.hasSwipedScreen) { swiped in
            // User swiped mid-peek: collapse the peek smoothly so the
            // composite offset doesn't jump when the real screen
            // transition fires alongside it.
            if swiped, peekOffset != 0 {
                withAnimation(.pageSwipe) { peekOffset = 0 }
            }
        }
        .onChange(of: model.edgeBump) { bump in
            // Rubber-band at the carousel ends: an over-swipe nudges
            // the row 12pt toward the attempted direction and springs
            // back, so the dead-end gesture reads as "you're at the
            // edge" instead of a dropped input. The bumpOffset == 0
            // guard swallows Shift+wheel tick spam while a bump is
            // already in flight.
            guard let bump, bumpOffset == 0 else { return }
            withAnimation(.easeOut(duration: 0.10)) {
                bumpOffset = bump.direction > 0 ? -12 : 12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                    bumpOffset = 0
                }
            }
        }
    }

    private func schedulePeek() {
        // 0.40s lets the panel's openMorph + content fade-in settle
        // (~0.42s + ~0.28s) before the peek begins, so the discoverability
        // beat is its own gesture instead of competing with the entrance.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            guard !screenPref.hasSwipedScreen else { return }
            // This is horizontal navigation affordance, so use the same
            // page curve as real swipes. It feels connected to the carousel
            // instead of to the panel's physical resize.
            withAnimation(.pageSwipe) { peekOffset = -46 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                guard !screenPref.hasSwipedScreen else { return }
                withAnimation(.pageSwipe) { peekOffset = 0 }
            }
        }
    }
}
