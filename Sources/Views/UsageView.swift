import SwiftUI
import AppKit

/// Usage data row — two ChartsBlocks (Claude / Codex) with a hairline
/// vertical divider. The chrome (provider titles, footer chip + page dots
/// + sync status) lives in `PanelHeader` / `PanelFooter` so it stays fixed
/// while this row swipes between usage and cost screens.
struct UsageView: View {
    @ObservedObject private var store = UsageStore.shared
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    private var style: ChartStyle { pref.style }

    var body: some View {
        HStack(spacing: 0) {
            ChartsBlock(
                color: visibility.claudeVisible ? IslandColor.claude : .white.opacity(0.32),
                usage: visibility.claudeVisible ? store.claude : .dummy,
                style: style, seed: 1
            )
            .opacity(visibility.claudeVisible ? 1 : 0.55)
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.06), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 1)
                .padding(.vertical, 8)
            ChartsBlock(
                color: visibility.codexVisible ? IslandColor.codex : .white.opacity(0.32),
                usage: visibility.codexVisible ? store.codex : .dummy,
                style: style, seed: 3
            )
            .opacity(visibility.codexVisible ? 1 : 0.55)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

struct ChartsBlock: View {
    let color: Color
    let usage: AppUsage
    let style: ChartStyle
    let seed: Int

    var body: some View {
        HStack(spacing: 18) {
            ChartTile(style: style, color: color, label: "5h",
                      window: usage.fiveHour, seed: seed)
            ChartTile(style: style, color: color, label: "week",
                      window: usage.weekly, seed: seed + 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

struct ChartTile: View {
    let style: ChartStyle
    let color: Color
    let label: String
    let window: WindowUsage
    let seed: Int

    /// Locked tile height across all 5 styles so the panel size is
    /// identical regardless of what the user picks.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        let value = window.usedPercent * 100   // 0-100
        let sub = subCaption()

        Group {
            switch style {
            case .ring:    RingChart(value: value, color: color, label: label, sub: sub)
            case .bar:     BarChart(value: value, color: color, label: label, sub: sub)
            case .stepped: SteppedChart(value: value, color: color, label: label, sub: sub)
            case .numeric: NumericChart(value: value, color: color, label: label, sub: sub)
            case .spark:   SparkChart(value: value, color: color, label: label, sub: sub, seed: seed)
            }
        }
        .id(style)
        // Blur + scale + opacity, all on the same strong ease-out at 220ms.
        // The blur masks the geometric mismatch between Ring and Bar so the
        // crossfade reads as one morph instead of two stacked objects.
        .transition(.chartSwap.animation(.chartSwap))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
    }

    private func subCaption() -> String {
        if let err = window.error { return err }
        guard let r = window.resetAt else { return "" }
        let delta = max(0, r.timeIntervalSinceNow)
        return "resets in \(formatDelta(delta))"
    }

    private func formatDelta(_ s: TimeInterval) -> String {
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s/60))m" }
        if s < 86400 { return "\(Int(s/3600))h" }
        return "\(Int(s/86400))d"
    }
}
