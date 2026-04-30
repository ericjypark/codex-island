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
                    withAnimation(.easeOut(duration: 0.25)) { peekOffset = 0 }
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
            // Reuse the panel-open spring so the peek inherits the same
            // motion identity that brought the panel into view. Springs
            // also hand off cleanly to a real swipe if the user grabs
            // mid-peek (both gestures animate via the same physics).
            withAnimation(.openMorph) { peekOffset = -46 }
            // Out spring settles ~0.42s; hold ~0.20s past settle, then
            // return with closeMorph — snappier, matching the asymmetric
            // open/close pace already established for the panel itself.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                guard !screenPref.hasSwipedScreen else { return }
                withAnimation(.closeMorph) { peekOffset = 0 }
            }
        }
    }
}
