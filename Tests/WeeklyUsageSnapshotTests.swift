import Foundation

enum L10n {
    static let locale = Locale(identifier: "en_US")
    static func tr(_ text: String, _ arguments: CVarArg...) -> String { String(format: text, arguments: arguments) }
}

@main
struct WeeklyUsageSnapshotTests {
    static var assertions = 0

    static func expect(_ result: Bool, _ message: String) {
        guard result else { print("FAIL: \(message)"); exit(1) }
        assertions += 1
    }

    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        calendar.firstWeekday = 1
        func date(_ value: String) -> Date {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            guard let date = formatter.date(from: value) else { fatalError("Invalid fixture date") }
            return date
        }
        func bucket(_ value: String, _ tokens: Int) -> DailyTokenBucket {
            DailyTokenBucket(dayStart: date(value), tokens: tokens, billableTokens: tokens / 10)
        }

        let now = date("2026-09-10 13:00")
        let recent = WeeklyCardPeriod.lastSevenDays.interval(now: now, calendar: calendar)
        expect(recent.start == date("2026-09-04 00:00") && recent.end == date("2026-09-11 00:00"),
               "last seven days includes today and the six preceding local dates")
        let sunday = WeeklyCardPeriod.lastSevenDays.interval(now: date("2026-09-13 23:59"), calendar: calendar)
        expect(sunday.start == date("2026-09-07 00:00") && sunday.end == date("2026-09-14 00:00"),
               "Sunday includes the current day instead of selecting a completed week")
        let midnight = WeeklyCardPeriod.lastSevenDays.interval(now: date("2026-09-11 00:00"), calendar: calendar)
        expect(midnight.start == date("2026-09-05 00:00") && midnight.end == date("2026-09-12 00:00"),
               "the seven-day window advances at local midnight")

        let spring = WeeklyCardPeriod.lastSevenDays.interval(now: date("2026-03-09 12:00"), calendar: calendar)
        expect(spring.duration == 167 * 3600, "spring-forward week uses calendar arithmetic")
        let fall = WeeklyCardPeriod.lastSevenDays.interval(now: date("2026-11-02 12:00"), calendar: calendar)
        expect(fall.duration == 169 * 3600, "fall-back week uses calendar arithmetic")
        let springCard = WeeklyUsageSnapshot.make(buckets: [:], period: .lastSevenDays,
                                                   now: date("2026-03-09 12:00"), calendar: calendar)
        expect(springCard.days.count == 7 && Set(springCard.days.map(\.date)).count == 7,
               "DST week has exactly seven distinct daily buckets")
        expect(springCard.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 },
               "day labels stay at midnight across DST")

        let month = WeeklyCardPeriod.thisMonth.interval(now: now, calendar: calendar)
        let year = WeeklyCardPeriod.thisYear.interval(now: now, calendar: calendar)
        expect(month.start == date("2026-09-01 00:00") && month.end == date("2026-09-11 00:00"),
               "this month begins on the first and ends after today")
        expect(year.start == date("2026-01-01 00:00") && year.end == date("2026-09-11 00:00"),
               "this year begins January first and ends after today")
        expect(WeeklyCardPeriod.allCases.map(\.title) == ["Last 7 days", "This month", "Last 3 months", "This year", "All time"],
               "period selection contains exactly the five agreed ranges")
        expect(WeeklyUsageSnapshot.make(buckets: [:], now: now, calendar: calendar).interval == recent,
               "the default snapshot covers the rolling seven-day window")
        let threeMonths = WeeklyCardPeriod.lastThreeMonths.interval(now: now, calendar: calendar)
        expect(threeMonths.start == date("2026-06-11 00:00") && threeMonths.end == date("2026-09-11 00:00"),
               "last three months is a rolling calendar window ending after today")
        let january = WeeklyCardPeriod.lastThreeMonths.interval(now: date("2026-01-10 12:00"), calendar: calendar)
        expect(january.start == date("2025-10-11 00:00") && january.end == date("2026-01-11 00:00"),
               "three months crosses New Year without dropping prior-year dates")
        let leapQuarter = WeeklyCardPeriod.lastThreeMonths.interval(now: date("2024-05-30 12:00"), calendar: calendar)
        expect(leapQuarter.start == date("2024-02-29 00:00"), "calendar month subtraction clamps correctly at leap February")
        expect(WeeklyCardPeriod.lastThreeMonths.needsExtendedHistory(now: date("2026-03-30 12:00"), calendar: calendar)
            && !WeeklyCardPeriod.lastThreeMonths.needsExtendedHistory(now: date("2026-03-31 12:00"), calendar: calendar),
               "older history loads only when the three-month range crosses the retained year")
        let quarter = WeeklyUsageSnapshot.make(buckets: [.codex: [
            bucket("2025-10-10 00:00", 999), bucket("2025-10-11 00:00", 10),
            bucket("2025-12-31 00:00", 20), bucket("2026-01-10 00:00", 30), bucket("2026-01-11 00:00", 999)
        ]], period: .lastThreeMonths, now: date("2026-01-10 12:00"), calendar: calendar)
        expect(quarter.totalTokens == 60 && quarter.days.count == 92 && quarter.activeDays == 3,
               "three-month totals include both boundaries and previous-year usage without future data")
        expect(quarter.shareText().contains("Three months with AI")
            && quarter.shareText(metric: .apiValue).contains("over the last 3 months"),
               "both captions identify the three-month period")
        expect(WeeklyValueMilestone.earned(dollars: 1000)?.headline(for: .lastThreeMonths) == "Four figures. 3 months.",
               "the earned money headline follows the three-month period")
        let leap = WeeklyUsageSnapshot.make(buckets: [:], period: .thisYear,
                                            now: date("2024-03-01 12:00"), calendar: calendar)
        expect(leap.days.count == 61 && leap.days.contains { $0.date == date("2024-02-29 00:00") },
               "year-to-date retains leap day")
        let dstMonth = WeeklyUsageSnapshot.make(buckets: [:], period: .thisMonth,
                                                now: date("2026-03-09 12:00"), calendar: calendar)
        expect(dstMonth.days.count == 9 && dstMonth.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 },
               "month-to-date stays on local midnights across daylight saving")
        let longHistory: [IslandProvider: [DailyTokenBucket]] = [
            .claude: [bucket("2022-01-01 00:00", 0), bucket("2024-02-29 12:00", 100),
                      bucket("2025-12-31 12:00", 200), bucket("2026-01-01 00:00", 300),
                      bucket("2026-08-31 00:00", 400), bucket("2026-09-01 00:00", 500),
                      bucket("2026-09-10 00:00", 600), bucket("2026-09-11 00:00", 999_999)],
            .codex: [bucket("2026-09-05 00:00", 700)]
        ]
        let allTime = WeeklyUsageSnapshot.make(buckets: longHistory, period: .allTime, now: now, calendar: calendar)
        let monthCard = WeeklyUsageSnapshot.make(buckets: longHistory, period: .thisMonth, now: now, calendar: calendar)
        let yearCard = WeeklyUsageSnapshot.make(buckets: longHistory, period: .thisYear, now: now, calendar: calendar)
        expect(allTime.interval.start == date("2024-02-29 00:00") && allTime.totalTokens == 2800,
               "all time starts at the oldest positive record and rejects future data")
        expect(allTime.days.last?.date == date("2026-09-10 00:00") && allTime.activeDays == 7,
               "all-time activity counts only days with usage")
        expect(monthCard.days.count == 10 && monthCard.totalTokens == 1800 && monthCard.activeDays == 3,
               "month totals exclude previous months and use the actual day count")
        expect(yearCard.days.count == 253 && yearCard.totalTokens == 2500,
               "year totals exclude prior years without losing January usage")
        let filteredHistory = WeeklyUsageSnapshot.make(buckets: longHistory, included: [.codex], period: .allTime,
                                                       now: now, calendar: calendar)
        expect(filteredHistory.interval.start == date("2026-09-05 00:00") && filteredHistory.totalTokens == 700,
               "all-time range and totals follow selected providers")
        let emptyHistory = WeeklyUsageSnapshot.make(buckets: longHistory, included: [], period: .allTime,
                                                    now: now, calendar: calendar)
        expect(emptyHistory.days.count == 1 && emptyHistory.totalTokens == 0,
               "empty all-time selections have a finite one-day range")
        expect(allTime.dateLabel.contains("2024") && allTime.dateLabel.contains("2026"),
               "all-time date range prints both years")
        for card in [monthCard, yearCard, allTime] {
            expect(card.chartPointIndices.first == 0 && card.chartPointIndices.last == card.days.count
                && card.chartPointIndices.count <= 67,
                   "long-range chart keeps both endpoints with bounded drawing work")
            expect(card.chartLabelDayIndices.count <= 5 && card.chartLabelDayIndices.allSatisfy { card.days.indices.contains($0) },
                   "long-range date labels stay sparse and inside the selected range")
            expect(card.cumulativeValues(for: .claude, metric: .tokens).last == Double(card.providers.first { $0.provider == .claude }?.tokens ?? 0),
                   "cumulative chart ends at the complete provider total")
            expect(!card.shareText().contains("My week") && !card.shareText(metric: .apiValue).contains("in 7 days"),
                   "longer-period captions never describe a seven-day result")
        }
        expect(monthCard.shareText().contains("3/10 active days") && yearCard.shareText().contains("My year with AI"),
               "captions identify the selected range and active-day denominator")
        expect(WeeklyValueMilestone.earned(dollars: 1000)?.headline(for: .thisMonth) == "Four-figure month."
            && WeeklyValueMilestone.earned(dollars: 1000)?.headline(for: .allTime) == "Four-figure total.",
               "earned money headlines identify the selected period")
        let historicalEvent = TokenEvent(provider: .codex, timestamp: date("2024-02-29 12:00"), model: "gpt-5",
                                         inputTokens: 10, outputTokens: 2, cacheCreationTokens: 3, cacheReadTokens: 5)
        let completeCost = CostSummary.summarize(events: [historicalEvent], now: now, includeAllHistory: true)
        let boundedCost = CostSummary.summarize(events: [historicalEvent], now: now)
        expect(completeCost.dailyTokens.reduce(0) { $0 + $1.tokens } == 20 && boundedCost.dailyTokens.allSatisfy { $0.tokens == 0 },
               "on-demand history retains older years without expanding normal refresh history")
        expect(completeCost.today.tokens == 0 && completeCost.month.tokens == 0,
               "older history does not inflate current cost windows")

        let buckets: [IslandProvider: [DailyTokenBucket]] = [
            .claude: [bucket("2026-09-03 00:00", 99_000), bucket("2026-09-04 00:00", 100),
                      bucket("2026-09-04 15:00", 200), bucket("2026-09-10 00:00", 900),
                      bucket("2026-09-11 00:00", 99_000)],
            .codex: [bucket("2026-09-05 00:00", 500)],
            .grok: [bucket("2026-09-05 00:00", 1)],
            .antigravity: [bucket("2026-09-06 00:00", -500)]
        ]
        let summary = WeeklyUsageSnapshot.make(buckets: buckets, now: now, calendar: calendar)
        expect(summary.totalTokens == 1701, "all providers and cache tokens counted, boundaries excluded")
        expect(summary.days.first?.total == 300, "duplicate local-day buckets are combined")
        expect(summary.activeDays == 3, "active days counted across providers without duplication")
        expect(summary.peakDay?.date == date("2026-09-10 00:00"), "today's usage can be the peak day")
        expect(summary.days.count == 7 && summary.days.last?.total == 900
            && summary.dateLabel == "Sep 4 – Sep 10, 2026",
               "the card contains exactly seven days with today's total and the matching date range")
        expect(summary.providers.map(\.provider) == [.claude, .codex, .grok], "ranked provider mix excludes empty totals")
        expect(summary.percentLabel(for: 1) == "<1%", "small nonzero shares never read as zero")
        expect(summary.providers.reduce(0) { $0 + $1.tokens } == summary.days.reduce(0) { $0 + $1.total },
               "chart, legend and headline share one total")
        let filtered = WeeklyUsageSnapshot.make(buckets: buckets, included: [.codex], now: now, calendar: calendar)
        expect(filtered.totalTokens == 500 && filtered.activeDays == 1 && filtered.providers.count == 1,
               "provider selection filters every displayed statistic")
        let empty = WeeklyUsageSnapshot.make(buckets: buckets, included: [], now: now, calendar: calendar)
        expect(empty.totalTokens == 0 && empty.activeDays == 0 && empty.peakDay == nil && empty.days.count == 7,
               "empty selection preserves date structure without invented activity")

        let newYear = WeeklyUsageSnapshot.make(buckets: [.codex: [bucket("2025-12-31 00:00", 42)]],
                                                now: date("2026-01-05 10:00"), calendar: calendar)
        expect(newYear.totalTokens == 42, "January share includes previous-year history")
        expect(newYear.dateLabel.contains("2025") && newYear.dateLabel.contains("2026"),
               "cross-year cards print both years")
        expect(CostSummary.localHistoryDays(now: date("2026-01-02 10:00")) == 14,
               "log scans retain a complete prior week near New Year")
        let event = TokenEvent(provider: .codex, timestamp: date("2025-12-31 12:00"), model: "gpt-5",
                               inputTokens: 10, outputTokens: 2, cacheCreationTokens: 3, cacheReadTokens: 5)
        let future = TokenEvent(provider: .codex, timestamp: date("2026-01-03 12:00"), model: "gpt-5",
                                inputTokens: 1000, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0)
        let cost = CostSummary.summarize(events: [event, future], now: date("2026-01-02 10:00"))
        expect(cost.dailyTokens.reduce(0) { $0 + $1.tokens } == 20, "cost pipeline retains December and rejects future events")
        expect(cost.dailyTokens.reduce(0) { $0 + $1.billableTokens } == 12, "cache-inclusive and billable totals stay distinct")

        expect(WeeklyUsageSnapshot.compactTokens(0).value == "0", "zero formatting")
        expect(WeeklyUsageSnapshot.compactTokens(999_999).unit == "M", "rounding promotes suffix instead of 1000K")
        expect(WeeklyUsageSnapshot.compactTokens(1_250_000_000).value == "1.3", "billions retain meaningful precision")
        let demo = WeeklyUsageSnapshot.make(buckets: buckets, now: now, calendar: calendar, isDemo: true, hasPartialRecords: true)
        expect(demo.shareText().contains("Demo week") && demo.shareText().contains("Partial local records"),
               "demo and incomplete sources remain labeled in shared copy")
        expect(summary.shareText().contains("Includes cache tokens") && summary.shareText().contains("https://codexisland.com"),
               "share caption defines the metric and provides a make-your-own path")

        let oldCache = Data("{\"dayStart\":0,\"tokens\":123,\"billableTokens\":12}".utf8)
        let restored = try JSONDecoder().decode(DailyTokenBucket.self, from: oldCache)
        expect(restored.tokens == 123 && restored.dollars == nil,
               "pre-price caches decode as unknown value, never a fabricated zero")
        expect(!summary.hasPricedUsage && summary.hasPartialPricing,
               "legacy token-only history does not become a zero-dollar card")
        let pricedBuckets: [IslandProvider: [DailyTokenBucket]] = [
            .claude: [DailyTokenBucket(dayStart: date("2026-09-04 00:00"), tokens: 100, billableTokens: 50,
                                      dollars: 1000.25, unpricedTokens: 0),
                      DailyTokenBucket(dayStart: date("2026-09-10 00:00"), tokens: 100, billableTokens: 50,
                                      dollars: 234.31, unpricedTokens: 0),
                      DailyTokenBucket(dayStart: date("2026-09-11 00:00"), tokens: 100, billableTokens: 50,
                                      dollars: 999, unpricedTokens: 0)],
            .codex: [DailyTokenBucket(dayStart: date("2026-09-05 00:00"), tokens: 900, billableTokens: 500,
                                     dollars: 45.50, unpricedTokens: 0)]
        ]
        let priced = WeeklyUsageSnapshot.make(buckets: pricedBuckets, now: now, calendar: calendar)
        expect(abs(priced.totalDollars - 1280.06) < 0.000001, "weekly API value sums same calendar days as tokens")
        expect(priced.hasPricedUsage && !priced.hasPartialPricing, "complete prices enable money spotlight")
        expect(priced.rankedProviders(for: .apiValue).first?.provider == .claude
            && priced.rankedProviders(for: .tokens).first?.provider == .codex,
               "provider ranking follows the chosen metric")
        let running = priced.cumulativeValues(for: .claude, metric: .apiValue)
        expect(running.count == 8 && running.first == 0 && abs((running.last ?? 0) - 1234.56) < 0.000001,
               "cumulative curve starts at zero and ends at the priced provider total")
        expect(zip(running, running.dropFirst()).allSatisfy { $0 <= $1 }, "empty days plateau in cumulative spending")
        let pricedSelection = WeeklyUsageSnapshot.make(buckets: pricedBuckets, included: [.codex], now: now, calendar: calendar)
        expect(pricedSelection.totalDollars == 45.50 && pricedSelection.totalTokens == 900,
               "provider filter changes dollars and tokens together")
        expect(priced.valueMilestone?.label == "$1K" && pricedSelection.valueMilestone == nil,
               "milestone reflects only the providers included in the card")
        expect(priced.tier(for: .apiValue) == .black && priced.tier(for: .tokens) == .white,
               "the spotlight selects independent money and token color thresholds")
        expect(pricedSelection.tier(for: .apiValue) == .white, "provider filtering recalculates the earned color")
        expect(priced.shareText(metric: .apiValue).contains("Black card")
            && priced.shareText(metric: .tokens).contains("White card"),
               "shared captions identify the same earned color as the card")
        for metric in WeeklyCardMetric.allCases {
            for tier in [WeeklyCardTier.black, .blue] {
                let minimum = tier.minimum(for: metric)
                let step = metric == .apiValue ? 0.001 : 1.0
                expect(WeeklyCardTier.earned(value: minimum, metric: metric) == tier
                    && WeeklyCardTier.earned(value: minimum - step, metric: metric) != tier,
                       "color tiers require the actual money or token threshold")
            }
            expect([Double.nan, .infinity, -1, 0].allSatisfy { WeeklyCardTier.earned(value: $0, metric: metric) == .white },
                   "missing or invalid usage cannot unlock a special color")
        }
        expect(WeeklyCardTier.black.minimum(for: .apiValue) == 1000 && WeeklyCardTier.blue.minimum(for: .apiValue) == 10_000,
               "money colors unlock at one thousand and ten thousand USD")
        expect(WeeklyCardTier.black.minimum(for: .tokens) == 100_000_000 && WeeklyCardTier.blue.minimum(for: .tokens) == 1_000_000_000,
               "token colors unlock at one hundred million and one billion")
        let beforeBlack = WeeklyUsageSnapshot.compactTokens(99_999_999)
        let beforeBlue = WeeklyUsageSnapshot.compactTokens(999_999_999)
        expect(beforeBlack.value + beforeBlack.unit == "99.9M" && beforeBlue.value + beforeBlue.unit == "999.9M",
               "compact token labels never imply a higher color tier through rounding")
        for (threshold, label) in [(100.0, "$100"), (1000, "$1K"), (10_000, "$10K"), (100_000, "$100K"),
                                   (1_000_000, "$1M"), (10_000_000, "$10M"), (100_000_000, "$100M"), (1_000_000_000, "$1B")] {
            expect(WeeklyValueMilestone.earned(dollars: threshold)?.label == label
                && WeeklyValueMilestone.earned(dollars: threshold - 0.001)?.label != label,
                   "milestones require the actual threshold, not a rounded display value")
        }
        expect([Double.nan, .infinity, -1, 0, 99.99].allSatisfy { WeeklyValueMilestone.earned(dollars: $0) == nil },
               "invalid prices and amounts below the first threshold never earn a badge")
        expect(priced.shareText(metric: .apiValue).hasPrefix("Four-figure week. $1,280.06 in 7 days."),
               "caption leads with the same earned title and amount as the image")
        var partialBuckets = pricedBuckets
        partialBuckets[.grok] = [DailyTokenBucket(dayStart: date("2026-09-06 00:00"), tokens: 500, billableTokens: 500,
                                                 dollars: 0, unpricedTokens: 500)]
        let partial = WeeklyUsageSnapshot.make(buckets: partialBuckets, now: now, calendar: calendar)
        expect(partial.hasPartialPricing && partial.valueSuffix == "+" && partial.hasPricedUsage,
               "unpriced models produce an explicit lower-bound estimate")
        expect(partial.valueMilestone?.label == "$1K", "unpriced tokens cannot inflate the earned milestone")
        expect(partial.tier(for: .apiValue) == .black && summary.tier(for: .apiValue) == .white,
               "unpriced tokens and legacy caches cannot inflate the money color tier")
        expect(partial.shareText(metric: .apiValue).contains("$1,280.06+")
            && partial.shareText(metric: .apiValue).contains("not a bill"),
               "money caption preserves both partial-pricing and estimate qualifiers")
        for invalid in [Double.nan, Double.infinity, -1] {
            let bad = WeeklyUsageSnapshot.make(buckets: [.grok: [DailyTokenBucket(dayStart: date("2026-09-06 00:00"), tokens: 2, billableTokens: 2,
                                                                                 dollars: invalid)]], now: now, calendar: calendar)
            expect(!bad.hasPricedUsage && bad.hasPartialPricing, "invalid prices cannot create a money card")
        }
        let free = WeeklyUsageSnapshot.make(buckets: [.grok: [DailyTokenBucket(dayStart: date("2026-09-06 00:00"), tokens: 2, billableTokens: 2,
                                                                              dollars: 0, unpricedTokens: 0)]], now: now, calendar: calendar)
        expect(free.hasPricedUsage && !free.hasPartialPricing, "known free usage stays distinct from missing pricing")
        expect(WeeklyUsageSnapshot.money(1234.56) == "$1,234.56", "grouped USD amount retains cents")
        expect(WeeklyUsageSnapshot.money(999.9999) == "$999.99", "display does not round up into an unearned milestone")
        expect(WeeklyUsageSnapshot.money(1294.9099999999) == "$1,294.91", "ordinary sums retain cent rounding despite floating-point noise")
        expect(WeeklyUsageSnapshot.money(0.0001) == "<$0.01", "subcent activity never looks free")
        let roundTrip = try JSONDecoder().decode(DailyTokenBucket.self,
                                                 from: JSONEncoder().encode(pricedBuckets[.claude]?[0]))
        expect(roundTrip.dollars == 1000.25 && roundTrip.unpricedTokens == 0, "daily API pricing survives cache round trip")
        expect(abs(cost.dailyTokens.compactMap(\.dollars).reduce(0, +) - Pricing.cost(for: event)) < 0.000001,
               "weekly history uses the same token-category pricing as the cost screen")
        let unknown = TokenEvent(provider: .codex, timestamp: now, model: "unknown-test-model-no-rates",
                                 inputTokens: 10, outputTokens: 2, cacheCreationTokens: 3, cacheReadTokens: 5)
        let unknownCost = CostSummary.summarize(events: [unknown], now: now)
        expect(unknownCost.dailyTokens.compactMap(\.unpricedTokens).reduce(0, +) == 20,
               "unpriced daily history retains cache tokens in coverage accounting")
        let recoveredBucket = DailyTokenBucket(dayStart: date("2026-01-09 00:00"), tokens: 1000, billableTokens: 100,
                                               dollars: 0, unpricedTokens: 1000, recoveredTokens: 1000)
        let recoveredCard = WeeklyUsageSnapshot.make(buckets: [.claude: [recoveredBucket]], period: .thisYear,
                                                      now: now, calendar: calendar)
        expect(recoveredCard.hasRecoveredHistory && recoveredCard.recoveredTokens == 1000,
               "the selected period exposes recovered daily history")
        expect(recoveredCard.hasPartialPricing && !recoveredCard.hasPricedUsage,
               "recovered totals without a model never create a fabricated API price")
        expect(recoveredCard.shareText().contains("Includes recovered daily totals on their original dates."),
               "shared captions explain recovered dates")
        let excludedRecovery = WeeklyUsageSnapshot.make(buckets: [.claude: [recoveredBucket]], included: [.codex],
                                                         period: .thisYear, now: now, calendar: calendar)
        expect(!excludedRecovery.hasRecoveredHistory, "excluded providers do not show a recovery note")
        let recoveryRoundTrip = try JSONDecoder().decode(DailyTokenBucket.self, from: JSONEncoder().encode(recoveredBucket))
        expect(recoveryRoundTrip.recoveredTokens == 1000, "recovery attribution survives the display cache")
        testLaunchGate()
        print("PASS: \(assertions) weekly-card assertions")
    }

    static func testLaunchGate() {
        let suite = "WeeklyCardLaunchTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Could not create test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = WeeklyCardLaunchGate(defaults: defaults)
        expect(!gate.prepare(version: "", existingInstallation: true), "missing build version never triggers a prompt")
        expect(!gate.prepare(version: "0.2.4", existingInstallation: false), "fresh installs establish a baseline without an update prompt")
        expect(!gate.prepare(version: "0.2.4", existingInstallation: true), "normal restart does not reopen the card")
        expect(gate.prepare(version: "0.2.5", existingInstallation: true), "upgrades queue a card presentation")
        let relaunched = WeeklyCardLaunchGate(defaults: defaults)
        expect(relaunched.prepare(version: "0.2.5", existingInstallation: true), "pending presentation survives exit before usage loads")
        relaunched.complete(version: "0.2.5")
        expect(!gate.prepare(version: "0.2.5", existingInstallation: true), "completed presentation remains dismissed after relaunch")
        expect(!gate.prepare(version: "0.2.3", existingInstallation: true), "downgrade does not count as an update")
        expect(!gate.prepare(version: "0.2.5", existingInstallation: true), "returning from a downgrade does not repeat a seen version")
        expect(gate.prepare(version: "0.2.10", existingInstallation: true), "component-wise version comparison handles multi-digit updates")
        gate.complete(version: "0.2.4")
        expect(gate.isPending(version: "0.2.10"), "completing another version cannot consume the current prompt")
        defaults.removePersistentDomain(forName: suite)
        expect(gate.prepare(version: "0.2.5", existingInstallation: true), "existing users without version tracking receive the feature introduction")
        gate.complete(version: "0.2.5")
        expect(!gate.prepare(version: "0.2.5", existingInstallation: true), "legacy migration introduction is also shown only once")
    }
}
