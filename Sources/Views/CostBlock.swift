import SwiftUI

/// Two cost cells per provider — Today + month-to-date — laid out
/// horizontally to mirror `ChartsBlock`'s 5h+week pair on the usage screen.
struct CostBlock: View {
    let color: Color
    let cost: ProviderCost
    let loading: Bool

    var body: some View {
        HStack(spacing: 18) {
            CostTile(color: color, window: cost.today, loading: loading, isMonth: false)
            CostTile(color: color, window: cost.month, loading: loading, isMonth: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

/// One cost cell. Branches on `CostStylePref.style` for the hero
/// visualization — pure dollars, value multiplier vs a $20/mo baseline,
/// raw token throughput, or a cumulative trend line. Cmd-click on the
/// expanded panel cycles styles (handled in `IslandRootView`).
struct CostTile: View {
    let color: Color
    let window: CostWindow
    let loading: Bool
    let isMonth: Bool

    @ObservedObject private var stylePref = CostStylePref.shared

    /// "Pro/Plus" subscription value — the implicit baseline the value
    /// multiplier compares against. Hardcoded because asking the user to
    /// configure their plan in Settings adds friction; $20/mo is the
    /// most common tier across both providers and serves as a relatable
    /// "subscription dollar" yardstick.
    private static let baselineMonthlyUSD: Double = 20

    /// Locked to match `ChartTile.tileHeight` so swipe transitions don't
    /// reflow the panel.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(resetGlyph)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)

            Group {
                switch stylePref.style {
                case .dollar: dollarHero
                case .multi:  multiplierHero
                case .tokens: tokensHero
                case .spark:  sparkHero
                }
            }
            .id(stylePref.style)
            .transition(.chartSwap.animation(.chartSwap))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
        .opacity(loading ? 0.7 : 1.0)
        .animation(.easeOut(duration: 0.18), value: loading)
    }

    // MARK: - Heroes

    private var dollarHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("$")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            CountUpDollar(target: window.dollars, color: color, glowOpacity: glowOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var multiplierHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(formattedMultiplier)
                .font(.system(size: 38, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .shadow(color: color.opacity(glowOpacity), radius: 6)
                .shadow(color: color.opacity(glowOpacity * 0.5), radius: 14)
                .numericTransition(value: multiplier)
                .animation(.strongEaseOut, value: multiplier)
            Text("×")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color.opacity(0.85))
                .shadow(color: color.opacity(glowOpacity * 0.6), radius: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tokensHero: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(tokensValue)
                .font(.system(size: 38, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .shadow(color: color.opacity(glowOpacity), radius: 6)
                .shadow(color: color.opacity(glowOpacity * 0.5), radius: 14)
            Text(tokensUnit)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sparkHero: some View {
        ZStack(alignment: .bottomTrailing) {
            CostSparkline(series: window.series, color: color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Small dollar overlay anchored to the bottom-right so the
            // sparkline gets the full cell but the user still has the
            // numeric anchor they can read at a glance.
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("$")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(formattedDollarsCompact)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.7), radius: 3)
            }
        }
    }

    // MARK: - Derived values

    private var multiplier: Double {
        let denom = isMonth ? Self.baselineMonthlyUSD : (Self.baselineMonthlyUSD / 30.0)
        guard denom > 0 else { return 0 }
        return window.dollars / denom
    }

    private var formattedMultiplier: String {
        let m = multiplier
        if m < 0.1 { return "0" }
        if m < 10 { return String(format: "%.1f", m) }
        return String(format: "%.0f", m)
    }

    private var tokensValue: String {
        let n = window.tokens
        let v = Double(n)
        if n < 1_000 { return "\(n)" }
        if n < 10_000 { return String(format: "%.1f", v / 1_000) }
        if n < 1_000_000 { return String(format: "%.0f", v / 1_000) }
        if n < 1_000_000_000 { return String(format: "%.1f", v / 1_000_000) }
        return String(format: "%.1f", v / 1_000_000_000)
    }

    private var tokensUnit: String {
        let n = window.tokens
        if n < 1_000 { return "tok" }
        if n < 1_000_000 { return "k" }
        if n < 1_000_000_000 { return "M" }
        return "B"
    }

    private var formattedDollarsCompact: String {
        let v = window.dollars
        if v < 100 { return String(format: "%.2f", v) }
        return String(format: "%.0f", v)
    }

    /// Glow intensity scales softly with spend so a quiet day stays calm
    /// and a heavy month looks luminous. Logarithmic so the curve doesn't
    /// blow out at the high end. Caps around 0.85 so even at peak the
    /// glow stays a halo, not a smear.
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
}
