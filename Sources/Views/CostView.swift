import SwiftUI

/// Cost data row. Mirrors `UsageView`'s data-row shape so swipe transitions
/// between them don't reflow the panel. Chrome (provider titles, footer
/// chip + page dots + sync status) lives in `PanelHeader` / `PanelFooter`.
///
/// Branches on `(claudeOn, codexOn)` from `ProviderVisibilityStore`:
///   - both on:  two `CostBlock`s with a hairline divider (default).
///   - one on:   the live block on its native side (centered tiles, since
///               its half doubled), hairline, then a per-model dollar
///               breakdown filling the freed half.
///   - both off: a centered `BothHiddenPlaceholder`.
struct CostView: View {
    @ObservedObject private var store = CostStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    var body: some View {
        let claudeOn = visibility.claudeVisible
        let codexOn = visibility.codexVisible

        HStack(spacing: 0) {
            switch (claudeOn, codexOn) {
            case (true, true):
                CostBlock(color: IslandColor.claude, cost: store.claude,
                          loading: store.claudeLoading, provider: .claude,
                          centerWhenSingle: false)
                hairline
                CostBlock(color: IslandColor.codex, cost: store.codex,
                          loading: store.codexLoading, provider: .codex,
                          centerWhenSingle: false)
            case (true, false):
                CostBlock(color: IslandColor.claude, cost: store.claude,
                          loading: store.claudeLoading, provider: .claude,
                          centerWhenSingle: true)
                hairline
                PerModelCostBreakdown(provider: .claude)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                    .transition(breakdownTransition)
            case (false, true):
                PerModelCostBreakdown(provider: .codex)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                    .transition(breakdownTransition)
                hairline
                CostBlock(color: IslandColor.codex, cost: store.codex,
                          loading: store.codexLoading, provider: .codex,
                          centerWhenSingle: true)
            case (false, false):
                BothHiddenPlaceholder()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// Mirror of `UsageView.breakdownTransition` — kept inline (not extracted
    /// to a shared helper) because it's two views and the transition's
    /// emotional purpose is "this half has been repurposed for the
    /// breakdown", which is a per-page editorial choice.
    private var breakdownTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97))
    }

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, .white.opacity(0.06), .clear],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}
