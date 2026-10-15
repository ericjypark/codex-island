import Foundation

enum WeeklyCardTier: String, CaseIterable, Identifiable {
    case white, black, blue

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func minimum(for metric: WeeklyCardMetric) -> Double {
        switch self {
        case .white: return 0
        case .black: return metric == .apiValue ? 1_000 : 100_000_000
        case .blue: return metric == .apiValue ? 10_000 : 1_000_000_000
        }
    }

    func thresholdLabel(for metric: WeeklyCardMetric) -> String {
        let value = minimum(for: metric)
        if metric == .apiValue { return WeeklyUsageSnapshot.money(value, cents: false) + "+" }
        let count = WeeklyUsageSnapshot.compactTokens(Int(value))
        return "\(count.value)\(count.unit)+"
    }

    static func earned(value: Double, metric: WeeklyCardMetric) -> Self {
        guard value.isFinite else { return .white }
        return allCases.reversed().first { value >= $0.minimum(for: metric) } ?? .white
    }

    static func earned(usdDollars: Double, quote: CurrencyQuote) -> Self {
        guard let club = WeeklyValueMilestone.earned(amount: quote.converted(usd: usdDollars)) else {
            return .white
        }
        // Color changes at a displayed club boundary, never within the same club.
        let thresholds = quote.currency.colorClubThresholds
        if club.minimumAmount >= thresholds.blue { return .blue }
        if club.minimumAmount >= thresholds.black { return .black }
        return .white
    }
}
