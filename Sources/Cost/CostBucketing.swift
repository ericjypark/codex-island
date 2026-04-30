import Foundation

/// Time-window helpers for the cost screen. All in calendar-local time so
/// "today" and "month-to-date" line up with what the user expects from a
/// glance at the wall clock.
enum CostBucketing {
    /// Fixed-scale ceiling for the today bar. v1: shared between providers
    /// for visual symmetry. Sized so a heavy Claude Code day (~$50-100 of
    /// API-equivalent spend) lands in the upper half of the bar without
    /// saturating immediately.
    static let todayCap: Double = 100

    /// Fixed-scale ceiling for the month-to-date bar. Sized to roughly match
    /// 20-25 working days × todayCap so a power user's monthly spend stays
    /// readable as a fill fraction.
    static let monthCap: Double = 2000

    /// Filter to events whose timestamp falls between local midnight today
    /// and now.
    static func eventsForToday(_ events: [TokenEvent], in tz: TimeZone = .current) -> [TokenEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let startOfDay = cal.startOfDay(for: Date())
        return events.filter { $0.timestamp >= startOfDay }
    }

    /// Filter to events from the first instant of the current calendar month
    /// (local) through now.
    static func eventsForMonthToDate(_ events: [TokenEvent], in tz: TimeZone = .current) -> [TokenEvent] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let start = cal.date(from: comps) else { return events }
        return events.filter { $0.timestamp >= start }
    }

    /// Short month name for the current month in the user's locale, e.g. "Apr".
    static func currentMonthLabel() -> String {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: Date())
    }

    /// Caption for the today cell — always "resets at midnight" since the
    /// reset is uniform.
    static let todayResetCaption = "resets at midnight"

    /// Caption like "resets in 12d" — counts days remaining in the current
    /// calendar month.
    static func monthResetCaption() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now),
              let day = cal.dateComponents([.day], from: now).day else {
            return "resets next month"
        }
        let remaining = max(0, range.count - day)
        if remaining == 0 { return "resets tomorrow" }
        if remaining == 1 { return "resets in 1d" }
        return "resets in \(remaining)d"
    }
}
