import Foundation

/// One time-bucket of estimated dollar spend (today's, this month's, etc).
/// No "cap" or fill metaphor — the dollar number is the load-bearing
/// display. The cost screen visualizes spend as a glowing brand-colored
/// number whose aura grows softly with the amount, so heavier usage feels
/// like an achievement rather than a burned-through budget.
struct CostWindow {
    let dollars: Double
    let tokens: Int
    let label: String
    let resetCaption: String
    let error: String?

    static let unknown = CostWindow(
        dollars: 0, tokens: 0, label: "—",
        resetCaption: "no data", error: "no data"
    )
}

/// Per-provider cost summary: today + month-to-date in calendar-local time.
struct ProviderCost {
    var today: CostWindow
    var month: CostWindow

    static let empty = ProviderCost(
        today: CostWindow(
            dollars: 0, tokens: 0, label: "today",
            resetCaption: CostBucketing.todayResetCaption, error: nil
        ),
        month: CostWindow(
            dollars: 0, tokens: 0,
            label: CostBucketing.currentMonthLabel(),
            resetCaption: CostBucketing.monthResetCaption(), error: nil
        )
    )

    /// Placeholder values shown when a provider is toggled off in Settings.
    /// Non-zero so the visualization remains meaningful (mirrors the
    /// `AppUsage.dummy` pattern used by UsageView).
    static let dummy = ProviderCost(
        today: CostWindow(
            dollars: 11.25, tokens: 1_240_000, label: "today",
            resetCaption: CostBucketing.todayResetCaption, error: nil
        ),
        month: CostWindow(
            dollars: 142.0, tokens: 18_500_000,
            label: CostBucketing.currentMonthLabel(),
            resetCaption: CostBucketing.monthResetCaption(), error: nil
        )
    )
}
