import SwiftUI

/// Cost data row — two CostBlocks (Claude / Codex) with a hairline vertical
/// divider. Mirrors `UsageView`'s data-row shape so swipe transitions
/// between them don't reflow the panel. Chrome (provider titles, footer
/// chip + page dots + sync status) lives in `PanelHeader` / `PanelFooter`.
struct CostView: View {
    @ObservedObject private var store = CostStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    var body: some View {
        HStack(spacing: 0) {
            CostBlock(
                color: visibility.claudeVisible ? IslandColor.claude : .white.opacity(0.32),
                cost: visibility.claudeVisible ? store.claude : .dummy,
                loading: store.claudeLoading,
                provider: .claude
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
                provider: .codex
            )
            .opacity(visibility.codexVisible ? 1 : 0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}
