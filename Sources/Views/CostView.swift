import SwiftUI

/// Cost data row. Mirrors `UsageView`'s data-row shape so swipe transitions
/// between them don't reflow the panel. Chrome (provider titles, footer
/// chip + page dots + sync status) lives in `PanelHeader` / `PanelFooter`.
struct CostView: View {
    @ObservedObject private var store = CostStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var connections = ProviderConnectionStore.shared
    @ObservedObject private var stylePref = CostStylePref.shared

    var body: some View {
        HStack(spacing: 0) {
            providerBlock(visibility.left)
            hairline
            if let right = visibility.right {
                providerBlock(right)
            } else {
                breakdown(for: visibility.left)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, IslandPanelLayout.columnInset)
            }
        }
        .frame(height: IslandPanelLayout.tileHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, IslandPanelLayout.horizontalInset)
    }

    @ViewBuilder
    private func providerBlock(_ provider: IslandProvider) -> some View {
        let cost = store.cost(for: provider)
        let snapshot = connections.snapshot(provider)
        if !provider.usesLegacyUsage && snapshot.hasNoActiveSubscription
            && cost.today.error != nil && cost.month.error != nil
            && cost.today.tokens == 0 && cost.month.tokens == 0
            && cost.today.dollars == 0 && cost.month.dollars == 0 {
            ProviderUsageEmptyState(provider: provider, snapshot: snapshot)
                .padding(.horizontal, IslandPanelLayout.columnInset)
        } else {
            CostBlock(color: provider.color, cost: cost,
                          loading: store.isLoading(provider), provider: provider.costProvider,
                          centerWhenSingle: visibility.right == nil)
            .help(store.localNotices[provider] ?? "Estimated API-equivalent cost from local CLI records; not a subscription charge.")
        }
    }

    /// Cost-page breakdown swaps metric to follow the visible tile: when
    /// the user has cycled to TOKENS (`stylePref.style == .tokens`), show
    /// per-model token volume; otherwise show per-model dollars. Both
    /// branches return the SAME view type and same row layout, so the
    /// metric swap re-uses the existing identity-based crossfade
    /// SwiftUI gives us inside `withAnimation` blocks (no explicit
    /// `.transition` needed here — only the (both-on)→(single) swap
    /// uses `breakdownTransition` to morph between completely different
    /// view trees).
    private func breakdown(for provider: AlertEngine.Provider) -> some View {
        let metric: PerModelBreakdown.Metric =
            stylePref.style == .tokens ? .tokens : .dollars
        return PerModelBreakdown(provider: provider, metric: metric)
            .id(metric)
            .transition(.chartSwap.animation(.chartSwap))
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
