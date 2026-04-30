import SwiftUI

/// Cost data row — two CostBlocks (Claude / Codex) with a hairline vertical
/// divider. Mirrors `UsageView`'s data-row shape so swipe transitions
/// between them don't reflow the panel. Chrome (provider titles, footer
/// chip + page dots + sync status) lives in `PanelHeader` / `PanelFooter`.
struct CostView: View {
    @ObservedObject private var store = CostStore.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    var body: some View {
        HStack(spacing: 0) {
            CostBlock(
                color: visibility.claudeVisible ? IslandColor.claude : .white.opacity(0.32),
                cost: visibility.claudeVisible ? store.claude : .dummy,
                loading: store.claudeLoading,
                subscriptionMonthlyUSD: subscriptionUSD(provider: .claude, plan: usageStore.claude.plan)
            )
            .opacity(visibility.claudeVisible ? 1 : 0.55)
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.06), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 1)
                .padding(.vertical, 8)
            CostBlock(
                color: visibility.codexVisible ? IslandColor.codex : .white.opacity(0.32),
                cost: visibility.codexVisible ? store.codex : .dummy,
                loading: store.codexLoading,
                subscriptionMonthlyUSD: subscriptionUSD(provider: .codex, plan: usageStore.codex.plan)
            )
            .opacity(visibility.codexVisible ? 1 : 0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// Map the provider-reported plan tag to its monthly USD price so the
    /// cost cells can show "X.Xx your sub". Anthropic's `subscriptionType`
    /// and OpenAI's `plan_type` use different vocabularies and the same
    /// "pro" tag means $20/mo on Claude but $200/mo on Codex.
    private func subscriptionUSD(provider: TokenEvent.Provider, plan: String?) -> Double? {
        guard let plan = plan?.lowercased() else { return nil }
        switch (provider, plan) {
        case (.claude, "pro"):  return 20
        case (.claude, "max"):  return 200
        case (.codex, "plus"):  return 20
        case (.codex, "pro"):   return 200
        default:                return nil   // free tier or unknown — skip ROI
        }
    }
}
