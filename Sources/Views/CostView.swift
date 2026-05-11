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
    @ObservedObject private var stylePref = CostStylePref.shared

    var body: some View {
        let visible = visibleProviders()

        HStack(spacing: 0) {
            if visible.isEmpty {
                BothHiddenPlaceholder()
                    .transition(.opacity)
            } else if visible.count == 1 {
                let p = visible[0]
                let costProvider: TokenEvent.Provider = {
                    switch p.provider {
                    case .claude: return .claude
                    case .codex:  return .codex
                    case .gemini: return .gemini
                    }
                }()
                CostBlock(color: p.color, cost: p.cost, loading: p.loading,
                          provider: costProvider, centerWhenSingle: true)
                hairline
                breakdown(for: p.provider)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                    .transition(breakdownTransition)
            } else {
                ForEach(visible, id: \.provider) { p in
                    if p.provider != visible.first?.provider {
                        hairline
                    }
                    let costProvider: TokenEvent.Provider = {
                        switch p.provider {
                        case .claude: return .claude
                        case .codex:  return .codex
                        case .gemini: return .gemini
                        }
                    }()
                    CostBlock(color: p.color, cost: p.cost, loading: p.loading,
                              provider: costProvider, centerWhenSingle: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private struct VisibleProvider {
        let provider: AlertEngine.Provider
        let color: Color
        let cost: ProviderCost
        let loading: Bool
    }

    private func visibleProviders() -> [VisibleProvider] {
        var out: [VisibleProvider] = []
        if visibility.claudeVisible {
            out.append(VisibleProvider(provider: .claude, color: IslandColor.claude, cost: store.claude, loading: store.claudeLoading))
        }
        if visibility.codexVisible {
            out.append(VisibleProvider(provider: .codex, color: IslandColor.codex, cost: store.codex, loading: store.codexLoading))
        }
        if visibility.geminiVisible {
            out.append(VisibleProvider(provider: .gemini, color: IslandColor.gemini, cost: store.gemini, loading: store.geminiLoading))
        }
        return out
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
