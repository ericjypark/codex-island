import Foundation

@main
struct MacHistoryReference {
    private struct Manifest: Decodable { let nowUnix: Double }
    private enum ReferenceError: Error { case invalidTimezone, unsupportedProvider }
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        let now = Date(timeIntervalSince1970: manifest.nowUnix)
        let payload = try JSONDecoder().decode(CatalogPayload.self, from: Data(contentsOf: directory.appendingPathComponent("model-prices-payload.json")))
        PricingCatalog.install(models: payload.models, fetchedAt: now)
        let ledger = UsageLedger(url: directory.appendingPathComponent("mac-usage-history.sqlite3"))
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "America/Chicago") else { throw ReferenceError.invalidTimezone }
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var buckets: [IslandProvider: [DailyTokenBucket]] = [:]
        var providers: [[String: Any]] = []
        let openCode = try ledger.savedSnapshot(source: .openCode)
        for provider in IslandProvider.allCases {
            guard let source = UsageLedger.Source(rawValue: provider.rawValue) else { throw ReferenceError.unsupportedProvider }
            let snapshot = try ledger.savedSnapshot(source: source)
            let events = snapshot.events + openCode.events.filter { $0.provider.rawValue == provider.rawValue }
            let summary = CostSummary.summarize(events: events, now: now, includeAllHistory: true, historicalDays: snapshot.historicalDays)
            buckets[provider] = summary.dailyTokens
            func total(_ window: CostWindow) -> [String: Any] {
                ["tokens": window.tokens, "billableTokens": window.billableTokens, "dollars": window.dollars, "series": window.series]
            }
            func models(_ rows: [ModelUsageRow]) -> [[String: Any]] {
                rows.map { ["model": $0.model, "tokens": $0.tokens, "dollars": $0.dollars, "tokenShare": $0.percent * 100, "dollarShare": $0.dollarPercent * 100] }
            }
            let days: [[String: Any]] = summary.dailyTokens.filter { $0.tokens > 0 }.map {
                ["date": formatter.string(from: $0.dayStart), "tokens": $0.tokens, "billableTokens": $0.billableTokens,
                 "dollars": $0.dollars ?? 0, "unpricedTokens": $0.unpricedTokens ?? 0, "recoveredTokens": $0.recoveredTokens ?? 0]
            }
            providers.append(["id": provider.rawValue, "records": events.count, "today": total(summary.today), "month": total(summary.month),
                              "models": [models(summary.recentByModel), models(summary.weekByModel)], "days": days])
        }
        let cards: [[String: Any]] = WeeklyCardPeriod.allCases.map { period in
            let snapshot = WeeklyUsageSnapshot.make(buckets: buckets, period: period, now: now, calendar: calendar)
            let providers: [[String: Any]] = snapshot.providers.map {
                ["id": $0.provider.rawValue, "tokens": $0.tokens, "dollars": $0.dollars, "unpricedTokens": $0.unpricedTokens]
            }
            return ["period": period.rawValue, "tokens": snapshot.totalTokens, "dollars": snapshot.totalDollars,
                    "activeDays": snapshot.activeDays, "dayCount": snapshot.days.count, "providers": providers,
                    "recoveredTokens": snapshot.recoveredTokens, "tokenTier": snapshot.tier(for: .tokens).title,
                    "valueTier": snapshot.tier(for: .apiValue).title, "dateLabel": snapshot.dateLabel,
                    "captionTokens": snapshot.shareText(metric: .tokens), "captionValue": snapshot.shareText(metric: .apiValue)]
        }
        let report: [String: Any] = ["nowUnix": now.timeIntervalSince1970, "timezone": calendar.timeZone.identifier,
                                   "providers": providers, "cards": cards]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: directory.appendingPathComponent("mac-reference.json"), options: .atomic)
        print("Mac source reference exported: \(providers.count) providers, \(cards.count) card periods.")
    }
}
