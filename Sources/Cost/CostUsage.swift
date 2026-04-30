import Foundation

/// One time-bucket of estimated dollar spend (today's, this month's, etc).
/// `cap` is the fixed-scale ceiling the bar fills against — when `dollars`
/// exceeds `cap`, the bar saturates at full and the dollar number is the
/// load-bearing display.
struct CostWindow {
    let dollars: Double
    let cap: Double
    let label: String
    let resetCaption: String
    let error: String?

    var fillFraction: Double {
        guard cap > 0 else { return 0 }
        return min(1.0, dollars / cap)
    }

    static let unknown = CostWindow(
        dollars: 0, cap: 25, label: "—",
        resetCaption: "no data", error: "no data"
    )
}

/// Per-provider cost summary: today + month-to-date in calendar-local time.
struct ProviderCost {
    var today: CostWindow
    var month: CostWindow

    static let empty = ProviderCost(
        today: CostWindow(
            dollars: 0, cap: CostBucketing.todayCap, label: "today",
            resetCaption: "resets at midnight", error: nil
        ),
        month: CostWindow(
            dollars: 0, cap: CostBucketing.monthCap,
            label: CostBucketing.currentMonthLabel(),
            resetCaption: CostBucketing.monthResetCaption(), error: nil
        )
    )

    /// Placeholder values shown when a provider is toggled off in Settings.
    /// Non-zero so the chart visualization stays meaningful (mirrors the
    /// `AppUsage.dummy` pattern used by UsageView).
    static let dummy = ProviderCost(
        today: CostWindow(
            dollars: 11.25, cap: CostBucketing.todayCap, label: "today",
            resetCaption: "resets at midnight", error: nil
        ),
        month: CostWindow(
            dollars: 142.0, cap: CostBucketing.monthCap,
            label: CostBucketing.currentMonthLabel(),
            resetCaption: CostBucketing.monthResetCaption(), error: nil
        )
    )
}
