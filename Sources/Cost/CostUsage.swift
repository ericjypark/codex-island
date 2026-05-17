import Foundation

/// One time-bucket of estimated dollar spend (today's, this month's, etc).
/// No "cap" or fill metaphor — the dollar number is the load-bearing
/// display. The cost screen visualizes spend as a glowing brand-colored
/// number whose aura grows softly with the amount, so heavier usage feels
/// like an achievement rather than a burned-through budget.
struct CostWindow {
    let dollars: Double
    /// Sum of every token type that crossed the wire — input + output +
    /// cache_creation + cache_read. ccusage parity; what the TOKENS hero
    /// shows when `TokenCountMode.all` is selected.
    let tokens: Int
    /// Input + output only. Matches Anthropic's claude.ai stats dashboard,
    /// which excludes cache reads. Surfaced when `TokenCountMode.billable`
    /// is selected.
    let billableTokens: Int
    /// Cumulative dollar spend over the period — one point per hour for
    /// today, one per day for the month. Drives the sparkline visualization
    /// in the cost cell. Always monotonically non-decreasing.
    let series: [Double]
    let label: String
    let error: String?
    /// Sorted unique model names that contributed real (non-zero) token
    /// activity in this window but had no entry in the embedded pricing
    /// snapshot. Surfaced as a warning glyph so a freshly released model
    /// doesn't silently read as $0.
    let unknownModels: [String]

    static let unknown = CostWindow(
        dollars: 0, tokens: 0, billableTokens: 0, series: [], label: "—",
        error: "no data", unknownModels: []
    )
}

/// Per-model breakdown of token activity over a recent rolling window —
/// derived from local session logs, not the OAuth usage endpoint (Anthropic
/// doesn't expose this slice). Currently used by the prototype Repurpose
/// variant to surface "what's burning my quota right now".
struct ModelUsageRow {
    /// Canonical model identifier (date suffix stripped via Pricing).
    let model: String
    /// Pretty name for UI ("Opus 4.7", "Sonnet 4.6", etc.).
    let displayName: String
    /// Billable tokens (input + output) attributed to this model in the
    /// window. Cache reads are excluded so bars track what actually
    /// pressures the rate-limit counter.
    let tokens: Int
    /// Dollar cost attributed to this model in the window — full
    /// `Pricing.cost(for:)` total including cache rates so the row
    /// reads "what this model is actually costing me", not "what hit
    /// the rate-limit". Cost-page consumers display this directly.
    let dollars: Double
    /// Share of the window's total billable tokens, 0...1. Drives the
    /// bar fill on the usage breakdown.
    let percent: Double
    /// Share of the window's total dollar spend, 0...1. Drives the bar
    /// fill on the cost breakdown — different from `percent` because a
    /// cache-read-heavy model can have ~0 billable tokens but a sizable
    /// dollar contribution.
    let dollarPercent: Double
}

/// Calendar-local daily token total used by the overview contribution grid.
/// Stores both wire-level and billable totals so future views can choose the
/// metric without re-scanning session logs. The overview intentionally uses
/// wire-level volume.
struct DailyTokenBucket: Codable {
    let dayStart: Date
    let tokens: Int
    let billableTokens: Int
}

/// Per-provider cost summary: today + month-to-date in calendar-local time.
struct ProviderCost {
    var today: CostWindow
    var month: CostWindow
    /// Per-model breakdown over the last ~5 hours, sorted by tokens
    /// descending. Empty when the provider has no recent events. Approximates
    /// the rate-limited 5h window used by the live tiles.
    var recentByModel: [ModelUsageRow] = []
    /// Per-model breakdown over the rolling last 7 days, sorted by tokens
    /// descending. Approximates the weekly window used by the live tiles.
    var weekByModel: [ModelUsageRow] = []
    /// Calendar-local daily history, oldest first, with today included as
    /// the final bucket. Powers the overview contribution grid ranges.
    var dailyTokens: [DailyTokenBucket] = []

    static let empty = ProviderCost(
        today: CostWindow(
            dollars: 0, tokens: 0, billableTokens: 0, series: [],
            label: L10n.tr("Today"), error: nil, unknownModels: []
        ),
        month: CostWindow(
            dollars: 0, tokens: 0, billableTokens: 0, series: [],
            label: CostBucketing.currentMonthLabel(), error: nil,
            unknownModels: []
        ),
        recentByModel: [],
        weekByModel: [],
        dailyTokens: []
    )

    /// Placeholder values shown when a provider is toggled off in Settings.
    /// Non-zero so the visualization remains meaningful (mirrors the
    /// `AppUsage.dummy` pattern used by UsageView).
    static let dummy = ProviderCost(
        today: CostWindow(
            dollars: 11.25, tokens: 1_240_000, billableTokens: 124_000,
            series: [0.5, 1.2, 2.4, 3.6, 5.1, 7.0, 9.2, 11.25],
            label: L10n.tr("Today"), error: nil, unknownModels: []
        ),
        month: CostWindow(
            dollars: 142.0, tokens: 18_500_000, billableTokens: 1_850_000,
            series: [3, 8, 15, 22, 31, 40, 52, 65, 78, 90, 105, 120, 135, 142],
            label: CostBucketing.currentMonthLabel(), error: nil,
            unknownModels: []
        ),
        recentByModel: [],
        weekByModel: [],
        dailyTokens: []
    )
}
