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
    /// When the panel is in single-provider mode (the other provider is
    /// hidden, freeing the right half for the per-model breakdown), the
    /// visible cost column claims ~340pt instead of ~165pt. Centering the
    /// pair lets it read as a balanced duet rather than two cells pushed
    /// to one side with empty trailing whitespace.
    var centerWhenSingle: Bool = false

    var body: some View {
        HStack(spacing: 18) {
            CostTile(color: color, window: cost.today, loading: loading,
                     isMonth: false, provider: provider,
                     centered: centerWhenSingle)
            CostTile(color: color, window: cost.month, loading: loading,
                     isMonth: true, provider: provider,
                     centered: centerWhenSingle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, IslandPanelLayout.columnInset)
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
    /// True when the panel is in single-provider mode — see CostBlock.
    /// Centering keeps the Today / month pair visually balanced when the
    /// column doubles in width.
    let centered: Bool

    @ObservedObject private var stylePref = CostStylePref.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var connections = ProviderConnectionStore.shared
    @ObservedObject private var tokenMode = TokenCountModeStore.shared
    @ObservedObject private var currencyStore = CurrencyStore.shared

    /// Locked to match `ChartTile.tileHeight` so swipe transitions don't
    /// reflow the panel.
    private static let tileHeight = IslandPanelLayout.tileHeight

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.tr(window.label))
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(resetGlyph)
                    .font(Typography.caption)
                    .foregroundStyle(.white.opacity(window.unknownModels.isEmpty ? 0.4 : 0.5))
                    .help(resetGlyphSpoken)
                    .accessibilityLabel(resetGlyphSpoken)
            }
            .frame(maxWidth: centered ? 240 : .infinity)

            Group {
                if stylePref.style == .multi {
                    multiplierHero
                } else if window.error != nil || (stylePref.style != .tokens && costUnavailable) {
                    Text("—").font(Typography.chartValue).foregroundStyle(.white.opacity(0.4))
                } else {
                switch stylePref.style {
                case .dollar: dollarHero
                case .multi:  multiplierHero
                case .tokens: tokensHero
                case .spark:  sparkHero
                }
                }
            }
            .id(stylePref.style)
            .transition(.chartSwap.animation(.chartSwap))
            .frame(maxHeight: .infinity, alignment: .center)
            .frame(maxWidth: centered ? 240 : .infinity, alignment: centered ? .center : .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .top : .topLeading)
        .frame(height: Self.tileHeight)
        .opacity(loading ? 0.7 : 1.0)
        .animation(.easeOut(duration: 0.18), value: loading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.label)
        .accessibilityValue(spokenValue)
    }

    private var costUnavailable: Bool {
        window.error != nil || (window.dollars == 0 && !window.unknownModels.isEmpty)
    }

    private var spokenValue: String {
        if stylePref.style == .multi {
            let plan = subscriptionUSD == nil ? "unavailable" : formatBarDollars(planAmount)
            let you = costUnavailable ? "unavailable" : formatBarDollars(window.dollars)
            return L10n.tr("%@ %@ versus you %@", planLabel ?? L10n.tr("Plan"), plan, you)
        }
        if let error = window.error { return error }
        if stylePref.style != .tokens && window.dollars == 0 && !window.unknownModels.isEmpty {
            return "Cost unavailable: model pricing is missing"
        }
        switch stylePref.style {
        case .dollar:
            return currencyStore.formatted(usd: window.dollars)
        case .multi:
            let plan = formatBarDollars(planAmount)
            let you = formatBarDollars(window.dollars)
            return L10n.tr("%@ %@ versus you %@", planLabel ?? L10n.tr("Plan"), plan, you)
        case .tokens:
            return L10n.tr("%@%@ tokens", tokensValue, tokensUnit)
        case .spark:
            return L10n.tr("%@ cumulative", currencyStore.formatted(usd: window.dollars))
        }
    }

    // MARK: - Heroes

    private var dollarHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(currencyStore.displaySymbol)
                    .font(Typography.unit)
                    .foregroundStyle(.white.opacity(0.6))
                CountUpDollar(
                    target: currencyStore.converted(usd: window.dollars),
                    wholeUnits: currencyStore.displayUsesWholeUnits,
                    color: color,
                    glowOpacity: 0,
                    font: .system(size: 32, weight: .semibold, design: .monospaced)
                )
            }
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
        // Sized so barColumn's natural height (14 dollar text + 3 + bar + 3
        // + 13 label text) fits inside the cell's hero slot without the bars
        // overflowing upward into the "Today" header.
        let maxBarHeight: CGFloat = 36

        return HStack(alignment: .bottom, spacing: 14) {
            Spacer(minLength: 0)
            if subscriptionUSD == nil {
                VStack(spacing: 3) {
                    Text("—").font(Typography.bodyNumber)
                    Text("Plan").font(Typography.caption)
                }
                .foregroundStyle(.white.opacity(0.4))
                .help("Monthly USD reference price is not available for this plan.")
            } else {
            barColumn(
                amount: plan,
                label: planLabel ?? L10n.tr("Plan"),
                fill: .white.opacity(0.20),
                isYou: false,
                maxAmount: maxAmount,
                maxBarHeight: maxBarHeight
            )
            }
            if costUnavailable {
                VStack(spacing: 3) {
                    Text("—").font(Typography.bodyNumber)
                    Text(L10n.tr("You")).font(Typography.caption)
                }
                .foregroundStyle(.white.opacity(0.4))
            } else {
            barColumn(
                amount: spend,
                label: L10n.tr("You"),
                fill: color,
                isYou: true,
                maxAmount: maxAmount,
                maxBarHeight: maxBarHeight
            )
            }
            Spacer(minLength: 0)
        }
        // Intrinsic height + width-only fill: lets the parent VStack's
        // Spacer push the bars to the bottom of the cell, matching how
        // dollar/tokens heroes sit. Without this the bar HStack greedily
        // claims maxHeight: .infinity and top-anchors against the header,
        // which read as the header shifting on every style swap.
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(Typography.bodyNumber)
                .foregroundStyle(isYou ? color : .white.opacity(0.78))
                .lineLimit(1)
            ZStack(alignment: .bottom) {
                Color.clear.frame(width: 24, height: maxBarHeight)
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill)
                    .frame(width: 24, height: height)
                    .animation(.strongEaseOut, value: amount)
            }
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
        }
    }

    private var tokensHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tokensValue)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tokensUnit)
                    .font(Typography.unit)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(L10n.tr("Tokens"))
                .font(Typography.micro)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sparkHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(currencyStore.displaySymbol)
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.6))
                Text(formattedDollarsCompact)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            CostSparkline(series: window.series, color: color)
                .frame(height: 30)
        }
    }

    // MARK: - Derived values

    /// Monthly subscription cost in USD for this provider's currently
    /// detected plan tier. Auto-mapped from Anthropic's "subscriptionType"
    /// or OpenAI's "plan_type" so each provider's bar reflects its actual
    /// plan: Claude Pro $20 / Max $200, Codex Plus $20 / Pro $100 or $200.
    private var subscriptionUSD: Double? {
        // Illustrative demo baselines; do not infer live subscription pricing.
        if AppEnvironment.isDemo {
            if provider == .grok { return 30 }
            if provider == .antigravity { return 19.99 }
        }
        let plan: String? = {
            switch provider {
            case .claude: return usageStore.claude.plan?.lowercased()
            case .codex:  return usageStore.codex.plan?.lowercased()
            case .antigravity: return connections.snapshot(.antigravity).plan?.lowercased()
            case .grok: return connections.snapshot(.grok).plan?.lowercased()
            }
        }()
        guard let plan else { return nil }
        switch (provider, plan) {
        case (.claude, "pro"): return 20
        case (.claude, "max"): return 200
        case (.codex, "plus"): return 20
        case (.codex, "prolite"): return 100
        case (.codex, "pro"):  return 200
        case (.antigravity, "google ai pro"): return 19.99
        default: return nil
        }
    }

    /// Display name of the active plan (Pro / Max / Plus). Used as the
    /// label under the plan bar so the user always knows what the
    /// comparison is anchored to.
    private var planLabel: String? {
        if AppEnvironment.isDemo {
            if provider == .grok { return "SuperGrok" }
            if provider == .antigravity { return "AI Pro" }
        }
        let plan: String? = {
            switch provider {
            case .claude: return usageStore.claude.plan?.lowercased()
            case .codex:  return usageStore.codex.plan?.lowercased()
            case .antigravity: return connections.snapshot(.antigravity).plan?.lowercased()
            case .grok: return connections.snapshot(.grok).plan?.lowercased()
            }
        }()
        guard let plan else { return nil }
        switch (provider, plan) {
        case (.claude, "pro"): return "Pro"
        case (.claude, "max"): return "Max"
        case (.codex, "plus"): return "Plus"
        case (.codex, "prolite"): return "Pro"
        case (.codex, "pro"):  return "Pro"
        case (.antigravity, "google ai pro"): return "AI Pro"
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
        currencyStore.formatted(usd: v)
    }

    /// Honors the user's TokenCountMode setting: `.all` shows wire-level
    /// throughput (cache included, ccusage parity); `.billable` shows
    /// input + output only, matching Anthropic's claude.ai stats panel.
    private var displayedTokens: Int {
        switch tokenMode.mode {
        case .all:      return window.tokens
        case .billable: return window.billableTokens
        }
    }

    private var tokensValue: String {
        let n = displayedTokens
        let v = Double(n)
        if n < 1_000 { return "\(n)" }
        if n < 10_000 { return String(format: "%.1f", v / 1_000) }
        if n < 1_000_000 { return String(format: "%.0f", v / 1_000) }
        if n < 1_000_000_000 { return String(format: "%.1f", v / 1_000_000) }
        return String(format: "%.1f", v / 1_000_000_000)
    }

    private var tokensUnit: String {
        let n = displayedTokens
        if n < 1_000 { return "tok" }
        if n < 1_000_000 { return "k" }
        if n < 1_000_000_000 { return "M" }
        return "B"
    }

    private var formattedDollarsCompact: String {
        currencyStore.formatted(usd: window.dollars, includesSymbol: false)
    }

    /// Compact "↻ 5h" / "↻ 12d" countdown — computed at render time from
    /// the current clock so the panel always shows accurate time-remaining
    /// regardless of how stale the last refresh is. Uses the same "↻ 3h"
    /// caption shape as the usage tiles. When the embedded pricing snapshot is
    /// missing models that produced real spend in this window, the countdown is replaced with
    /// an "⚠ N unpriced" warning so the user knows the dollar total is an
    /// undercount rather than a clean zero.
    private var resetGlyph: String {
        if loading && window.error != nil { return "Loading" }
        if window.error != nil { return "No records" }
        if !window.unknownModels.isEmpty {
            return L10n.tr("⚠ %d unpriced", window.unknownModels.count)
        }
        return "↻ " + (isMonth ? CostBucketing.monthResetIn() : CostBucketing.todayResetIn())
    }

    private var resetGlyphSpoken: String {
        if let err = window.error { return err }
        if !window.unknownModels.isEmpty {
            return L10n.tr("Warning: %d unpriced models — totals may be incomplete.", window.unknownModels.count)
        }
        let countdown = isMonth ? CostBucketing.monthResetIn() : CostBucketing.todayResetIn()
        return L10n.tr("Resets in %@", countdown)
    }
}
