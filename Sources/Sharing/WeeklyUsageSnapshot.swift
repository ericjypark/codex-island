import Foundation

enum WeeklyCardMetric: String, CaseIterable, Identifiable {
    case apiValue, tokens
    var id: String { rawValue }
    var title: String { self == .apiValue ? "API value" : "Tokens" }
}

struct WeeklyValueMilestone {
    let minimumDollars: Double
    let label: String
    let headline: String

    private static let tiers: [Self] = [
        .init(minimumDollars: 1_000_000_000, label: "$1B", headline: "Billions. One week."),
        .init(minimumDollars: 100_000_000, label: "$100M", headline: "Nine-figure week."),
        .init(minimumDollars: 10_000_000, label: "$10M", headline: "Eight-figure week."),
        .init(minimumDollars: 1_000_000, label: "$1M", headline: "Seven-figure week."),
        .init(minimumDollars: 100_000, label: "$100K", headline: "Six-figure week."),
        .init(minimumDollars: 10_000, label: "$10K", headline: "Five-figure week."),
        .init(minimumDollars: 1_000, label: "$1K", headline: "Four-figure week."),
        .init(minimumDollars: 100, label: "$100", headline: "Three-figure week.")
    ]

    static func earned(dollars: Double) -> Self? {
        guard dollars.isFinite else { return nil }
        return tiers.first { dollars >= $0.minimumDollars }
    }

    func headline(for period: WeeklyCardPeriod) -> String {
        switch period {
        case .lastSevenDays: return headline
        case .thisMonth: return headline.replacingOccurrences(of: "week", with: "month")
        case .lastThreeMonths:
            return minimumDollars >= 1_000_000_000 ? "Billions. 3 months."
                : headline.replacingOccurrences(of: "-figure week.", with: " figures. 3 months.")
        case .thisYear: return headline.replacingOccurrences(of: "week", with: "year")
        case .allTime:
            return minimumDollars >= 1_000_000_000 ? "Billions. All time."
                : headline.replacingOccurrences(of: "week", with: "total")
        }
    }
}

enum WeeklyCardPeriod: String, CaseIterable, Identifiable {
    case lastSevenDays, thisMonth, lastThreeMonths, thisYear, allTime

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lastSevenDays: return "Last 7 days"
        case .thisMonth: return "This month"
        case .lastThreeMonths: return "Last 3 months"
        case .thisYear: return "This year"
        case .allTime: return "All time"
        }
    }

    var tokenHeadline: String {
        switch self {
        case .lastSevenDays: return "My week with AI."
        case .thisMonth: return "My month with AI."
        case .lastThreeMonths: return "Three months with AI."
        case .thisYear: return "My year with AI."
        case .allTime: return "My AI journey."
        }
    }

    var valueQualifier: String {
        switch self {
        case .lastSevenDays: return "In just 7 days."
        case .thisMonth: return "This month so far."
        case .lastThreeMonths: return "In just 3 months."
        case .thisYear: return "This year so far."
        case .allTime: return "All time."
        }
    }

    var tokenCallToAction: String {
        switch self {
        case .lastSevenDays: return "Your week. Your card."
        case .thisMonth: return "Your month. Your card."
        case .lastThreeMonths: return "Your AI. Your card."
        case .thisYear: return "Your year. Your card."
        case .allTime: return "Your AI. Your card."
        }
    }

    func interval(now: Date, calendar: Calendar, earliestRecord: Date? = nil) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let start: Date
        switch self {
        case .lastSevenDays:
            start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .thisMonth:
            start = calendar.dateInterval(of: .month, for: today)?.start ?? today
        case .lastThreeMonths:
            start = calendar.date(byAdding: .month, value: -3, to: end) ?? today
        case .thisYear:
            start = calendar.dateInterval(of: .year, for: today)?.start ?? today
        case .allTime:
            start = min(today, calendar.startOfDay(for: earliestRecord ?? today))
        }
        return DateInterval(start: start, end: end)
    }

    func needsExtendedHistory(now: Date, calendar: Calendar) -> Bool {
        if self == .allTime { return true }
        guard self == .lastThreeMonths else { return false }
        let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? now
        return interval(now: now, calendar: calendar).start < yearStart
    }
}

struct WeeklyUsageSnapshot {
    struct Day: Identifiable {
        let date: Date
        let tokens: [IslandProvider: Int]
        let dollars: [IslandProvider: Double]
        var id: Date { date }
        var total: Int { tokens.values.reduce(0, +) }
        var totalDollars: Double { dollars.values.reduce(0, +) }

        func value(for provider: IslandProvider, metric: WeeklyCardMetric) -> Double {
            metric == .apiValue ? dollars[provider] ?? 0 : Double(tokens[provider] ?? 0)
        }
    }

    struct ProviderTotal: Identifiable {
        let provider: IslandProvider
        let tokens: Int
        let dollars: Double
        let unpricedTokens: Int
        var id: IslandProvider { provider }
    }

    let period: WeeklyCardPeriod
    let interval: DateInterval
    let days: [Day]
    let providers: [ProviderTotal]
    let calendar: Calendar
    let isDemo: Bool
    let hasPartialRecords: Bool
    let recoveredTokens: Int

    var totalTokens: Int { providers.reduce(0) { $0 + $1.tokens } }
    var totalDollars: Double { providers.reduce(0) { $0 + $1.dollars } }
    var valueMilestone: WeeklyValueMilestone? { .earned(dollars: totalDollars) }
    var valueHeadline: String { valueMilestone?.headline(for: period) ?? "My AI tab." }
    var valueChallenge: String { valueMilestone == nil ? "What's your AI tab?" : "Can you top this?" }
    var hasPartialPricing: Bool { providers.contains { $0.unpricedTokens > 0 } }
    var hasRecoveredHistory: Bool { recoveredTokens > 0 }
    var hasPricedUsage: Bool { providers.contains { $0.tokens > $0.unpricedTokens } }
    var valueSuffix: String { hasPartialPricing || hasPartialRecords ? "+" : "" }
    var activeDays: Int { days.filter { $0.total > 0 }.count }
    var durationLabel: String { "\(days.count) \(days.count == 1 ? "day" : "days")" }
    var peakDay: Day? { days.filter { $0.total > 0 }.max { $0.total < $1.total } }

    static func make(
        buckets: [IslandProvider: [DailyTokenBucket]],
        included: Set<IslandProvider> = Set(IslandProvider.allCases),
        period: WeeklyCardPeriod = .lastSevenDays,
        now: Date = Date(),
        calendar: Calendar = .current,
        isDemo: Bool = false,
        hasPartialRecords: Bool = false
    ) -> WeeklyUsageSnapshot {
        let earliestRecord = included.flatMap { buckets[$0] ?? [] }
            .filter { $0.tokens > 0 && $0.dayStart <= now }.map(\.dayStart).min()
        let interval = period.interval(now: now, calendar: calendar, earliestRecord: earliestRecord)
        var totals: [Date: [IslandProvider: Int]] = [:]
        var dollars: [Date: [IslandProvider: Double]] = [:]
        var unpriced: [IslandProvider: Int] = [:]
        var recoveredTokens = 0
        for provider in IslandProvider.allCases where included.contains(provider) {
            for bucket in buckets[provider] ?? [] {
                let day = calendar.startOfDay(for: bucket.dayStart)
                guard day >= interval.start, day < interval.end, day <= now else { continue }
                let tokens = max(0, bucket.tokens)
                recoveredTokens += min(tokens, max(0, bucket.recoveredTokens ?? 0))
                totals[day, default: [:]][provider, default: 0] += tokens
                if let amount = bucket.dollars, amount.isFinite, amount >= 0 {
                    dollars[day, default: [:]][provider, default: 0] += amount
                    unpriced[provider, default: 0] += min(tokens, max(0, bucket.unpricedTokens ?? 0))
                } else {
                    unpriced[provider, default: 0] += tokens
                }
            }
        }
        let dayCount = max(1, calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
        let days = (0..<dayCount).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
            return Day(date: date, tokens: totals[date] ?? [:], dollars: dollars[date] ?? [:])
        }
        let providers = IslandProvider.allCases.compactMap { provider -> ProviderTotal? in
            let tokens = days.reduce(0) { $0 + ($1.tokens[provider] ?? 0) }
            return tokens > 0 ? ProviderTotal(provider: provider, tokens: tokens,
                                               dollars: days.reduce(0) { $0 + ($1.dollars[provider] ?? 0) },
                                               unpricedTokens: unpriced[provider] ?? 0) : nil
        }.sorted {
            if $0.tokens == $1.tokens { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.tokens > $1.tokens
        }
        return WeeklyUsageSnapshot(period: period, interval: interval, days: days, providers: providers,
                                   calendar: calendar, isDemo: isDemo,
                                   hasPartialRecords: hasPartialRecords, recoveredTokens: recoveredTokens)
    }

    var dateLabel: String {
        let end = days.last?.date ?? interval.start
        let sameYear = calendar.component(.year, from: interval.start) == calendar.component(.year, from: end)
        let startText = dateText(interval.start, format: sameYear ? "MMM d" : "MMM d, yyyy")
        return "\(startText) – \(dateText(end, format: "MMM d, yyyy"))"
    }

    var filenameDate: String { dateText(interval.start, format: "yyyy-MM-dd") }

    func dateText(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    func rankedProviders(for metric: WeeklyCardMetric) -> [ProviderTotal] {
        guard metric == .apiValue else { return providers }
        return providers.sorted {
            if $0.dollars == $1.dollars { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.dollars > $1.dollars
        }
    }

    func tier(for metric: WeeklyCardMetric) -> WeeklyCardTier {
        .earned(value: metric == .apiValue ? totalDollars : Double(totalTokens), metric: metric)
    }

    func cumulativeValues(for provider: IslandProvider, metric: WeeklyCardMetric) -> [Double] {
        var total = 0.0
        return [0] + days.map { day in
            total += day.value(for: provider, metric: metric)
            return total
        }
    }

    var chartLabelDayIndices: [Int] {
        if days.count <= 7 { return Array(days.indices) }
        return (1...5).map { max(0, Int((Double(days.count) * Double($0) / 5).rounded()) - 1) }
    }

    var chartPointIndices: [Int] {
        guard days.count > 31 else { return Array(0...days.count) }
        let step = max(1, Int(ceil(Double(days.count) / 60)))
        return Set([0, days.count] + Array(stride(from: step, to: days.count, by: step))
            + chartLabelDayIndices.map { $0 + 1 }).sorted()
    }

    func chartLabel(for day: Day) -> String {
        let format = days.count <= 7 ? "EEE" : days.count <= 366 ? "MMM d" : "MMM yy"
        return dateText(day.date, format: format).uppercased()
    }

    func shareText(metric: WeeklyCardMetric = .tokens) -> String {
        let count = Self.compactTokens(totalTokens)
        let stack = providers.map(\.provider.name).joined(separator: " + ")
        let demoLabel = period == .lastSevenDays ? "Demo week" : "Demo \(period.title.lowercased())"
        let qualifier = isDemo ? demoLabel : String(period.tokenHeadline.dropLast())
        let caveat = (hasPartialRecords ? " Partial local records." : "")
            + (hasRecoveredHistory ? " Includes recovered daily totals on their original dates." : "")
        if metric == .apiValue {
            let pricing = hasPartialPricing ? " Some tokens have no known price." : ""
            let timeframe = period == .lastThreeMonths ? "over the last 3 months" : "in \(durationLabel)"
            return """
            \(isDemo ? "Demo: " : "")\(valueHeadline) \(Self.money(totalDollars))\(valueSuffix) \(timeframe).
            \(tier(for: metric).title) card · \(count.value)\(count.unit) tokens incl. cache · \(stack)
            \(dateLabel)
            API-rate estimate (USD), not a bill.\(caveat)\(pricing)

            \(valueChallenge)
            https://codexisland.com
            """
        }
        return """
        \(qualifier): \(count.value)\(count.unit) tokens. \(activeDays)/\(days.count) active days.
        \(tier(for: metric).title) card · \(stack)
        \(dateLabel) · Includes cache tokens.\(caveat)

        \(period == .lastSevenDays ? "What does your week look like?" : "What does your AI usage look like?")
        Make your card with CodexIsland → https://codexisland.com
        """
    }

    static func money(_ amount: Double, cents: Bool = true) -> String {
        if cents && amount > 0 && amount < 0.01 { return "<$0.01" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = cents ? 2 : 0
        formatter.maximumFractionDigits = cents ? 2 : 0
        let precision = cents ? 100.0 : 1.0
        let rounded = (amount * precision).rounded() / precision
        // Keep normal cent rounding except when it would imply an unearned milestone.
        if rounded.isFinite,
           WeeklyValueMilestone.earned(dollars: rounded)?.label != WeeklyValueMilestone.earned(dollars: amount)?.label {
            formatter.roundingMode = .down
        }
        return formatter.string(from: NSNumber(value: amount.isFinite ? max(0, amount) : 0)) ?? "$0.00"
    }

    static func compactTokens(_ tokens: Int) -> (value: String, unit: String) {
        let count = max(0, tokens)
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (divisor, unit) in units where Double(count) >= divisor * 0.99995 {
            let raw = Double(count) / divisor
            var value = (raw * 10).rounded() / 10
            if WeeklyCardTier.earned(value: value * divisor, metric: .tokens)
                != WeeklyCardTier.earned(value: Double(count), metric: .tokens) {
                if raw < 1 { continue }
                value = (raw * 10).rounded(.down) / 10
            }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return (formatter.string(from: NSNumber(value: value)) ?? "0", unit)
        }
        return (String(count), "")
    }

    func percentLabel(for tokens: Int) -> String {
        let percent = totalTokens > 0 ? Double(tokens) / Double(totalTokens) * 100 : 0
        return percent > 0 && percent < 1 ? "<1%" : "\(Int(percent.rounded()))%"
    }
}
