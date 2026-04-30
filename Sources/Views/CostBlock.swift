import SwiftUI

/// Two cost cells per provider — Today + month-to-date — laid out
/// horizontally to mirror `ChartsBlock`'s 5h+week pair on the usage screen.
struct CostBlock: View {
    let color: Color
    let cost: ProviderCost
    let loading: Bool
    /// Identifies which provider this column is for so the VALUE multiplier
    /// can pick the right per-plan baseline (Claude Pro $20 vs Max $200,
    /// Codex Plus $20 vs Pro $200) and the caption can name the plan.
    let provider: TokenEvent.Provider

    var body: some View {
        HStack(spacing: 18) {
            CostTile(color: color, window: cost.today, loading: loading,
                     isMonth: false, provider: provider)
            CostTile(color: color, window: cost.month, loading: loading,
                     isMonth: true, provider: provider)
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
    let provider: TokenEvent.Provider

    @ObservedObject private var stylePref = CostStylePref.shared
    @ObservedObject private var usageStore = UsageStore.shared

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

    /// Side-by-side bar chart: left bar is the plan price (white, subtle),
    /// right bar is what the user actually spent (brand-colored, glowing).
    /// Heights are normalized to whichever bar is larger so the contrast
    /// reads at a glance — heavy use towers over the plan baseline, light
    /// use sits below it. Labels under each bar name what's being compared
    /// (the actual plan tier from UsageStore vs "you") so the user always
    /// knows the reference point.
    private var multiplierHero: some View {
        let plan = planAmount
        let spend = window.dollars
        let maxAmount = max(plan, spend, 0.0001)
        let maxBarHeight: CGFloat = 40

        return HStack(alignment: .bottom, spacing: 14) {
            Spacer(minLength: 0)
            barColumn(
                amount: plan,
                label: planLabel ?? "Plan",
                fill: .white.opacity(0.20),
                isYou: false,
                maxAmount: maxAmount,
                maxBarHeight: maxBarHeight
            )
            barColumn(
                amount: spend,
                label: "You",
                fill: color,
                isYou: true,
                maxAmount: maxAmount,
                maxBarHeight: maxBarHeight
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func barColumn(
        amount: Double,
        label: String,
        fill: Color,
        isYou: Bool,
        maxAmount: Double,
        maxBarHeight: CGFloat
    ) -> some View {
        let normalized = max(0, amount / maxAmount)
        let height = max(3, CGFloat(normalized) * maxBarHeight)

        return VStack(spacing: 3) {
            Text(formatBarDollars(amount))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(isYou ? color : .white.opacity(0.78))
                .lineLimit(1)
            ZStack(alignment: .bottom) {
                Color.clear.frame(width: 24, height: maxBarHeight)
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill)
                    .frame(width: 24, height: height)
                    .shadow(
                        color: isYou ? color.opacity(glowOpacity) : .clear,
                        radius: 5
                    )
                    .animation(.strongEaseOut, value: amount)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
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

    /// Monthly subscription cost in USD for this provider's currently
    /// detected plan tier. Auto-mapped from Anthropic's "subscriptionType"
    /// or OpenAI's "plan_type" so each provider's bar reflects its actual
    /// plan: Claude Pro $20 / Max $200, Codex Plus $20 / Pro $200.
    private var subscriptionUSD: Double? {
        let plan: String? = {
            switch provider {
            case .claude: return usageStore.claude.plan?.lowercased()
            case .codex:  return usageStore.codex.plan?.lowercased()
            }
        }()
        guard let plan else { return nil }
        switch (provider, plan) {
        case (.claude, "pro"): return 20
        case (.claude, "max"): return 200
        case (.codex, "plus"): return 20
        case (.codex, "pro"):  return 200
        default: return nil
        }
    }

    /// Display name of the active plan (Pro / Max / Plus). Used as the
    /// label under the plan bar so the user always knows what the
    /// comparison is anchored to.
    private var planLabel: String? {
        let plan: String? = {
            switch provider {
            case .claude: return usageStore.claude.plan?.lowercased()
            case .codex:  return usageStore.codex.plan?.lowercased()
            }
        }()
        guard let plan else { return nil }
        switch (provider, plan) {
        case (.claude, "pro"): return "Pro"
        case (.claude, "max"): return "Max"
        case (.codex, "plus"): return "Plus"
        case (.codex, "pro"):  return "Pro"
        default: return nil
        }
    }

    /// Plan reference for the bar chart — always the FULL monthly plan
    /// price, regardless of which cell. Subscriptions are monthly, so
    /// comparing today's spend against a daily portion would muddy the
    /// reference; comparing today's spend against the full month plan
    /// shows "you've already spent X% of a month's plan in one day"
    /// which is the more striking framing.
    private var planAmount: Double {
        subscriptionUSD ?? 0
    }

    private func formatBarDollars(_ v: Double) -> String {
        if v < 10 { return String(format: "$%.2f", v) }
        if v < 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.0f", v)
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

    /// Compact "↻ 5h" / "↻ 12d" countdown — computed at render time from
    /// the current clock so the panel always shows accurate time-remaining
    /// regardless of how stale the last refresh is. Mirrors `NumericChart`'s
    /// "↻ 3h" treatment so the cost screen doesn't introduce a new caption
    /// shape.
    private var resetGlyph: String {
        if let err = window.error { return err }
        return "↻ " + (isMonth ? CostBucketing.monthResetIn() : CostBucketing.todayResetIn())
    }
}
