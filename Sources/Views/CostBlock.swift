import SwiftUI

/// Two cost cells per provider — today + month-to-date — laid out horizontally
/// to mirror `ChartsBlock`'s 5h+week pair on the usage screen.
struct CostBlock: View {
    let color: Color
    let cost: ProviderCost
    let loading: Bool
    /// Monthly cost of the user's subscription in USD, used to compute the
    /// ROI multiplier on each cell. Nil when the plan is unknown or free —
    /// the cell then shows just the token brag without the "X.Xx" prefix.
    let subscriptionMonthlyUSD: Double?

    var body: some View {
        HStack(spacing: 18) {
            CostTile(
                color: color, window: cost.today, loading: loading,
                subscriptionMonthlyUSD: subscriptionMonthlyUSD, isMonth: false
            )
            CostTile(
                color: color, window: cost.month, loading: loading,
                subscriptionMonthlyUSD: subscriptionMonthlyUSD, isMonth: true
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

/// One cost cell. The dollar number is the hero — 38pt brand-colored
/// monospace digits with a soft glow whose intensity grows with the
/// amount, plus a count-up reveal on first appearance and a smooth
/// interpolation on refresh. Below it: a single small caption with the
/// ROI multiplier vs the user's subscription and the period's raw token
/// count, so heavy use reads as "look how much value I extracted" rather
/// than "look how much I burned."
struct CostTile: View {
    let color: Color
    let window: CostWindow
    let loading: Bool
    let subscriptionMonthlyUSD: Double?
    let isMonth: Bool

    /// Locked to match `ChartTile.tileHeight` so swipe transitions don't
    /// reflow the panel.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.lowercase)
                Spacer()
                Text(resetGlyph)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("$")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                CountUpDollar(target: window.dollars, color: color, glowOpacity: glowOpacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(captionText)
                .font(.system(size: 10).monospaced())
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
        .opacity(loading ? 0.7 : 1.0)
        .animation(.easeOut(duration: 0.18), value: loading)
    }

    /// Glow intensity scales softly with spend so a $5 day looks calm and a
    /// $1500 month looks luminous. Logarithmic so the curve doesn't blow
    /// out at the high end. Caps around 0.85 so even at peak the glow
    /// stays a halo, not a smear.
    private var glowOpacity: Double {
        let s = window.dollars
        if s <= 0 { return 0 }
        let scale = log(s + 1) / log(2000)
        return min(0.85, 0.20 + scale * 0.65)
    }

    /// Compact reset hint that mirrors `NumericChart`'s "↻ 3h" treatment so
    /// the cost screen doesn't introduce a new caption shape.
    private var resetGlyph: String {
        if let err = window.error { return err }
        return window.resetCaption
            .replacingOccurrences(of: "resets at ", with: "↻ ")
            .replacingOccurrences(of: "resets in ", with: "↻ ")
    }

    /// "X.Xx · Y.YM tok" combined caption. The ROI half drops cleanly when
    /// no subscription is known (Free plan, missing plan tag), leaving
    /// just the token brag so the cell is never empty.
    private var captionText: String {
        let tokens = formatTokens(window.tokens)
        guard let roi = roiText else { return tokens }
        return "\(roi) · \(tokens)"
    }

    /// "16.6x" when the multiplier is meaningful. Today divides by the
    /// daily portion of the subscription (sub/30) so a heavy day shows as
    /// 10x+; month divides by the full subscription so power users see
    /// 5-10x. Both feel like "I extracted way more value than I paid."
    private var roiText: String? {
        guard let sub = subscriptionMonthlyUSD, sub > 0 else { return nil }
        let denom = isMonth ? sub : (sub / 30.0)
        guard denom > 0 else { return nil }
        let mult = window.dollars / denom
        if mult < 0.1 { return "<0.1x" }
        if mult < 10 { return String(format: "%.1fx", mult) }
        return String(format: "%.0fx", mult)
    }

    private func formatTokens(_ n: Int) -> String {
        let v = Double(n)
        if n < 1_000 { return "\(n) tok" }
        if n < 10_000 { return String(format: "%.1fk tok", v / 1_000) }
        if n < 1_000_000 { return String(format: "%.0fk tok", v / 1_000) }
        if n < 1_000_000_000 { return String(format: "%.1fM tok", v / 1_000_000) }
        return String(format: "%.1fB tok", v / 1_000_000_000)
    }
}
