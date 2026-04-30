import Foundation

/// Time-window helpers for the cost screen. All in calendar-local time so
/// "today" and "month-to-date" line up with what the user expects from a
/// glance at the wall clock.
enum CostBucketing {
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

    /// Cumulative dollar spend bucketed by hour from local midnight to now.
    /// Returns one entry per elapsed hour (1–24 entries depending on time
    /// of day). Always monotonically non-decreasing — feeds the sparkline
    /// in the cost cell, which ascends as more spend accumulates.
    static func cumulativeHourly(_ events: [TokenEvent], in tz: TimeZone = .current) -> [Double] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        let currentHour = cal.dateComponents([.hour], from: now).hour ?? 0
        let buckets = currentHour + 1

        var spend = Array(repeating: 0.0, count: buckets)
        for event in events where event.timestamp >= startOfDay {
            let h = cal.dateComponents([.hour], from: event.timestamp).hour ?? 0
            if h < buckets { spend[h] += Pricing.cost(for: event) }
        }
        return runningSum(spend)
    }

    /// Cumulative dollar spend bucketed by day from the first of the month
    /// to today. Returns one entry per elapsed day.
    static func cumulativeDaily(_ events: [TokenEvent], in tz: TimeZone = .current) -> [Double] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let monthStart = cal.date(from: comps) else { return [] }
        let currentDay = (cal.dateComponents([.day], from: now).day ?? 1) - 1
        let buckets = currentDay + 1

        var spend = Array(repeating: 0.0, count: buckets)
        for event in events where event.timestamp >= monthStart {
            let d = (cal.dateComponents([.day], from: event.timestamp).day ?? 1) - 1
            if d < buckets { spend[d] += Pricing.cost(for: event) }
        }
        return runningSum(spend)
    }

    private static func runningSum(_ values: [Double]) -> [Double] {
        var out: [Double] = []
        out.reserveCapacity(values.count)
        var sum = 0.0
        for v in values { sum += v; out.append(sum) }
        return out
    }

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
