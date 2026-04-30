import Foundation

/// One time-bucket of estimated dollar spend (today's, this month's, etc).
/// No "cap" or fill metaphor — the dollar number is the load-bearing
/// display. The cost screen visualizes spend as a glowing brand-colored
/// number whose aura grows softly with the amount, so heavier usage feels
/// like an achievement rather than a burned-through budget.
struct CostWindow {
    let dollars: Double
    let tokens: Int
    /// Cumulative dollar spend over the period — one point per hour for
    /// today, one per day for the month. Drives the sparkline visualization
    /// in the cost cell. Always monotonically non-decreasing.
    let series: [Double]
    let label: String
    let error: String?

    static let unknown = CostWindow(
        dollars: 0, tokens: 0, series: [], label: "—",
        error: "no data"
    )
}

/// Per-provider cost summary: today + month-to-date in calendar-local time.
struct ProviderCost {
    var today: CostWindow
    var month: CostWindow

    static let empty = ProviderCost(
        today: CostWindow(
            dollars: 0, tokens: 0, series: [], label: "Today", error: nil
        ),
        month: CostWindow(
            dollars: 0, tokens: 0, series: [],
            label: CostBucketing.currentMonthLabel(), error: nil
        )
    )

    /// Placeholder values shown when a provider is toggled off in Settings.
    /// Non-zero so the visualization remains meaningful (mirrors the
    /// `AppUsage.dummy` pattern used by UsageView).
    static let dummy = ProviderCost(
        today: CostWindow(
            dollars: 11.25, tokens: 1_240_000,
            series: [0.5, 1.2, 2.4, 3.6, 5.1, 7.0, 9.2, 11.25],
            label: "Today", error: nil
        ),
        month: CostWindow(
            dollars: 142.0, tokens: 18_500_000,
            series: [3, 8, 15, 22, 31, 40, 52, 65, 78, 90, 105, 120, 135, 142],
            label: CostBucketing.currentMonthLabel(), error: nil
        )
    )
}
