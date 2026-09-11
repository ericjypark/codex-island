import Foundation

/// Pure aggregation for the cost screen — a single pass over a flat
/// `[TokenEvent]` stream that splits it into today / this-month / rolling-5h /
/// rolling-7d windows, per-model breakdowns, and sparkline buckets.
///
/// Lives as a free `enum` so the detached refresh task in `CostStore` can call
/// it off the main actor without touching `@MainActor` state. `now` is
/// injectable so the window boundaries are testable.
enum CostSummary {
    static func summarize(events: [TokenEvent], now: Date = Date(), includeAllHistory: Bool = false,
                          historicalDays: [HistoricalUsageDay] = []) -> ProviderCost {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let startOfDay = cal.startOfDay(for: now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? startOfDay
        let currentHour = cal.dateComponents([.hour], from: now).hour ?? 0
        let currentDay = (cal.dateComponents([.day], from: now).day ?? 1) - 1
        let recovered = HistoricalUsageDay.supplements(historicalDays, events: events.filter { $0.timestamp <= now }, calendar: cal)
        var historyDays = localHistoryDays(now: now)
        let earliestEvent = events.lazy.filter({
            $0.timestamp <= now && $0.inputTokens + $0.outputTokens + $0.cacheCreationTokens + $0.cacheReadTokens > 0
        }).map(\.timestamp).min()
        let earliestRecovered = recovered.filter { $0.dayStart <= now }.map(\.dayStart).min()
        if includeAllHistory, let earliest = [earliestEvent, earliestRecovered].compactMap({ $0 }).min() {
            let recordedDays = (cal.dateComponents([.day], from: cal.startOfDay(for: earliest), to: startOfDay).day ?? 0) + 1
            historyDays = max(historyDays, recordedDays)
        }
        let historyStart = cal.date(
            byAdding: .day,
            value: -(historyDays - 1),
            to: startOfDay
        ) ?? startOfDay
        // Rolling windows for per-model breakdown — approximate the live
        // tile windows. We don't know the server's exact window alignment
        // for either, so "last N hours from now" is the practical proxy.
        // 5h matches Anthropic's rate-limit window; 7d matches both
        // providers' weekly tile.
        let recentStart = now.addingTimeInterval(-5 * 3600)
        let weekStart = now.addingTimeInterval(-7 * 24 * 3600)

        var todayDollars = 0.0, todayTokens = 0, todayBillable = 0
        var monthDollars = 0.0, monthTokens = 0, monthBillable = 0
        var hourlyBuckets = Array(repeating: 0.0, count: currentHour + 1)
        var dailyBuckets = Array(repeating: 0.0, count: currentDay + 1)
        var historyTokenBuckets = Array(repeating: 0, count: historyDays)
        var historyBillableBuckets = Array(repeating: 0, count: historyDays)
        var historyDollarBuckets = Array(repeating: 0.0, count: historyDays)
        var historyUnpricedBuckets = Array(repeating: 0, count: historyDays)
        var historyRecoveredBuckets = Array(repeating: 0, count: historyDays)
        // Filtered to non-zero token events so handshake/stub rows don't
        // show up as "unpriced" warnings — the user only cares about
        // models that actually moved tokens.
        var todayUnknown: Set<String> = []
        var monthUnknown: Set<String> = []
        // Per-canonical-model billable tokens + dollars within the recent
        // window. Cache reads excluded from `tokens` (they don't pressure
        // the rate-limit counter), included in `dollars` (they cost real
        // money). Two metrics, two consumers: usage-page shows tokens,
        // cost-page shows dollars.
        var recentTokensByModel: [String: Int] = [:]
        var recentDollarsByModel: [String: Double] = [:]
        // Same shape, weekly window. Two windows in one pass costs an
        // extra `>=` per event — cheap relative to JSON parsing upstream.
        var weekTokensByModel: [String: Int] = [:]
        var weekDollarsByModel: [String: Double] = [:]

        // Drop events older than every window's start. Using `min(...)`
        // matters here because the rolling 7-day window straddles month
        // boundaries: on May 3, weekStart is Apr 26, but `monthStart` is
        // May 1, so a `>= monthStart` guard would silently filter out
        // Apr 26–30 from the weekly slice. The 5h slice never had this
        // problem (5h ⊂ today ⊂ month), but adding weekly broke the
        // assumption — keep the broader guard.
        let earliestStart = min(monthStart, weekStart, historyStart)
        for event in events {
            guard event.timestamp >= earliestStart, event.timestamp <= now else { continue }
            let cost = Pricing.cost(for: event)
            // Two parallel running totals: `tokens` is the wire-level sum
            // (ccusage parity); `billable` is input + output only, matching
            // Anthropic's claude.ai stats panel which excludes cache tokens.
            // Persisting both lets the Settings toggle flip the displayed
            // figure instantly without re-scanning session logs.
            let billable = event.inputTokens + event.outputTokens
            let tokens = billable + event.cacheCreationTokens + event.cacheReadTokens
            let isUnpriced = tokens > 0 && !Pricing.isKnown(event.model)

            if event.timestamp >= historyStart {
                let eventDay = cal.startOfDay(for: event.timestamp)
                let dayOffset = cal.dateComponents([.day], from: historyStart, to: eventDay).day ?? -1
                if historyTokenBuckets.indices.contains(dayOffset) {
                    historyTokenBuckets[dayOffset] += tokens
                    historyBillableBuckets[dayOffset] += billable
                    historyDollarBuckets[dayOffset] += cost
                    if isUnpriced { historyUnpricedBuckets[dayOffset] += tokens }
                }
            }

            // Month aggregation gated separately now that the outer guard
            // is `min(monthStart, weekStart)` (so previous-month events
            // can reach the weekly slice).
            if event.timestamp >= monthStart {
                monthDollars += cost
                monthTokens += tokens
                monthBillable += billable
                let day = (cal.dateComponents([.day], from: event.timestamp).day ?? 1) - 1
                if day < dailyBuckets.count { dailyBuckets[day] += cost }
                if isUnpriced { monthUnknown.insert(event.model) }
            }

            // Today is a strict subset of month
            if event.timestamp >= startOfDay {
                todayDollars += cost
                todayTokens += tokens
                todayBillable += billable
                let hour = cal.dateComponents([.hour], from: event.timestamp).hour ?? 0
                if hour < hourlyBuckets.count { hourlyBuckets[hour] += cost }
                if isUnpriced { todayUnknown.insert(event.model) }
            }

            // Weekly rolling window slice — superset of recent, subset of
            // month (when month is short). Compute canonical name once and
            // reuse for the 5h slice to avoid double work.
            if event.timestamp >= weekStart {
                let canon = Pricing.canonicalModelName(event.model)
                if billable > 0 {
                    weekTokensByModel[canon, default: 0] += billable
                }
                if cost > 0 {
                    weekDollarsByModel[canon, default: 0] += cost
                }

                // 5h rolling window slice — strict subset of weekly.
                if event.timestamp >= recentStart {
                    if billable > 0 {
                        recentTokensByModel[canon, default: 0] += billable
                    }
                    if cost > 0 {
                        recentDollarsByModel[canon, default: 0] += cost
                    }
                }
            }
        }

        for bucket in recovered where bucket.dayStart >= historyStart && bucket.dayStart <= now {
            let offset = cal.dateComponents([.day], from: historyStart, to: bucket.dayStart).day ?? -1
            guard historyTokenBuckets.indices.contains(offset) else { continue }
            historyTokenBuckets[offset] += bucket.tokens
            historyBillableBuckets[offset] += bucket.billableTokens
            historyUnpricedBuckets[offset] += bucket.tokens
            historyRecoveredBuckets[offset] += bucket.tokens
            if bucket.dayStart >= monthStart {
                monthTokens += bucket.tokens
                monthBillable += bucket.billableTokens
                monthUnknown.insert("Recovered daily totals")
            }
            if bucket.dayStart == startOfDay {
                todayTokens += bucket.tokens
                todayBillable += bucket.billableTokens
                todayUnknown.insert("Recovered daily totals")
            }
        }

        let recentRows = modelRows(
            tokensByModel: recentTokensByModel,
            dollarsByModel: recentDollarsByModel
        )
        let weekRows = modelRows(
            tokensByModel: weekTokensByModel,
            dollarsByModel: weekDollarsByModel
        )

        return ProviderCost(
            today: CostWindow(
                dollars: todayDollars,
                tokens: todayTokens,
                billableTokens: todayBillable,
                series: runningSum(hourlyBuckets),
                label: "Today",
                error: nil,
                unknownModels: todayUnknown.sorted()
            ),
            month: CostWindow(
                dollars: monthDollars,
                tokens: monthTokens,
                billableTokens: monthBillable,
                series: runningSum(dailyBuckets),
                label: CostBucketing.currentMonthLabel(),
                error: nil,
                unknownModels: monthUnknown.sorted()
            ),
            recentByModel: recentRows,
            weekByModel: weekRows,
            dailyTokens: dailyTokenBuckets(
                start: historyStart,
                tokens: historyTokenBuckets,
                billableTokens: historyBillableBuckets,
                dollars: historyDollarBuckets,
                unpricedTokens: historyUnpricedBuckets,
                recoveredTokens: historyRecoveredBuckets,
                calendar: cal
            )
        )
    }

    static func localHistoryDays(now: Date = Date()) -> Int {
        // A complete previous week can cross New Year's Day.
        max(14, yearHistoryDays(now: now))
    }

    static func yearHistoryDays(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now)
        let yearStart = cal.date(from: cal.dateComponents([.year], from: today)) ?? today
        let yearDays = (cal.dateComponents([.day], from: yearStart, to: today).day ?? 0) + 1
        return max(1, yearDays)
    }

    private static func dailyTokenBuckets(
        start: Date,
        tokens: [Int],
        billableTokens: [Int],
        dollars: [Double],
        unpricedTokens: [Int],
        recoveredTokens: [Int],
        calendar: Calendar
    ) -> [DailyTokenBucket] {
        tokens.indices.map { index in
            let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
            return DailyTokenBucket(
                dayStart: day,
                tokens: tokens[index],
                billableTokens: billableTokens[index],
                dollars: dollars[index],
                unpricedTokens: unpricedTokens[index],
                recoveredTokens: recoveredTokens[index]
            )
        }
    }

    /// Build sorted `ModelUsageRow`s from the two parallel per-model maps
    /// for a given window. Shared between the 5h and weekly slices so
    /// both stay perfectly consistent in shape, sorting, and percent-share
    /// computation.
    private static func modelRows(
        tokensByModel: [String: Int],
        dollarsByModel: [String: Double]
    ) -> [ModelUsageRow] {
        let totalTokens = tokensByModel.values.reduce(0, +)
        let totalDollars = dollarsByModel.values.reduce(0, +)
        let canonicals = Set(tokensByModel.keys).union(dollarsByModel.keys)
        return canonicals.map { canon in
            let tokens = tokensByModel[canon] ?? 0
            let dollars = dollarsByModel[canon] ?? 0
            return ModelUsageRow(
                model: canon,
                displayName: prettyModelName(canon),
                tokens: tokens,
                dollars: dollars,
                percent: totalTokens > 0 ? Double(tokens) / Double(totalTokens) : 0,
                dollarPercent: totalDollars > 0 ? dollars / totalDollars : 0
            )
        }
        .sorted {
            // Tokens primary, dollars secondary — handles cache-read-only
            // rows (zero billable tokens, non-zero dollars) by sinking
            // them to the bottom but not disappearing.
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.dollars > $1.dollars
        }
    }

    /// Pretty-print the canonical model id for UI rows. Falls back to the
    /// raw id if no friendlier name is wired up yet — better than a blank.
    private static func prettyModelName(_ canonical: String) -> String {
        // Anthropic: "claude-opus-4-7" → "Opus 4.7"
        if canonical.hasPrefix("claude-") {
            let trimmed = String(canonical.dropFirst("claude-".count))
            // Split at first dash, then collapse remaining dashes into dots
            // so "opus-4-7" → "opus.4.7" → "Opus 4.7".
            guard let dash = trimmed.firstIndex(of: "-") else {
                return trimmed.capitalized
            }
            let family = String(trimmed[..<dash]).capitalized
            let version = trimmed[trimmed.index(after: dash)...]
                .replacingOccurrences(of: "-", with: ".")
            return "\(family) \(version)"
        }
        // OpenAI: keep as-is, just uppercase the GPT prefix.
        if canonical.hasPrefix("gpt-") {
            return canonical.replacingOccurrences(of: "gpt-", with: "GPT-")
        }
        // OpenAI reasoning family ("o3-pro", "o4-mini-high", etc.) — already
        // short and conventional, capitalize only the leading letter so it
        // matches the typographic weight of "GPT-..." / "Opus 4.7".
        if let first = canonical.first, first == "o", canonical.count > 1,
           canonical.dropFirst().first?.isNumber == true {
            return canonical.prefix(1).uppercased() + canonical.dropFirst()
        }
        return canonical
    }

    private static func runningSum(_ values: [Double]) -> [Double] {
        var out = [Double]()
        out.reserveCapacity(values.count)
        var sum = 0.0
        for v in values { sum += v; out.append(sum) }
        return out
    }
}
