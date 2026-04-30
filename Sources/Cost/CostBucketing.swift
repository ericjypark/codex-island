import Foundation

/// Time-window helpers for the cost screen. Calendar-local so "today" and
/// "this month" line up with the wall clock the user is glancing at.
///
/// Aggregation lives in `CostStore.summarize` (single-pass over all events).
/// What's left here is the chrome the cell labels need: month name + reset
/// countdowns.
enum CostBucketing {
    /// Short month name for the current month in the user's locale, e.g. "Apr".
    static func currentMonthLabel() -> String {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: Date())
    }

    /// Compact "time remaining until next local midnight" — `5h`, `42m`,
    /// `12s`. Computed on demand so the panel always shows the correct
    /// countdown regardless of how stale the last refresh is.
    static func todayResetIn() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        guard let nextMidnight = cal.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return "<1d" }
        let interval = nextMidnight.timeIntervalSince(now)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h"
    }

    /// Compact days-until-end-of-month: `12d`, `1d`. Always uses the same
    /// shape regardless of how close to month-end we are, so the cell
    /// caption never reverts to a phrase like "tomorrow".
    static func monthResetIn() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let day = cal.dateComponents([.day], from: now).day else {
            return "1d"
        }
        let remaining = max(1, range.count - day)
        return "\(remaining)d"
    }
}
