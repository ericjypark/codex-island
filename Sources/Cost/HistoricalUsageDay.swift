import Foundation

struct HistoricalUsageDay: Codable {
    let provider: TokenEvent.Provider
    let sourceIdentity: String
    let intervalStart: Date
    let intervalEnd: Date
    let sourceLocalDate: String
    let sourceUTCOffsetSeconds: Int
    let tokensIncludingCache: Int
    let inputPlusOutputTokens: Int

    var isValid: Bool {
        guard intervalStart.timeIntervalSince1970.isFinite, intervalEnd.timeIntervalSince1970.isFinite,
              intervalStart.timeIntervalSince1970 > 0,
              (23 * 3600 ... 25 * 3600).contains(intervalEnd.timeIntervalSince(intervalStart)),
              tokensIncludingCache > 0, tokensIncludingCache <= Int.max / 4,
              inputPlusOutputTokens >= 0, inputPlusOutputTokens <= tokensIncludingCache,
              let zone = TimeZone(secondsFromGMT: sourceUTCOffsetSeconds) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return displayDay(calendar: calendar) == intervalStart
    }

    func displayDay(calendar: Calendar) -> Date? {
        let values = sourceLocalDate.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        let parts = DateComponents(year: values[0], month: values[1], day: values[2])
        guard let date = calendar.date(from: parts) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == values[0], actual.month == values[1], actual.day == values[2] else { return nil }
        return date
    }

    static func supplements(_ days: [HistoricalUsageDay], events: [TokenEvent], calendar: Calendar) -> [DailyTokenBucket] {
        var output: [DailyTokenBucket] = []
        for provider in Set(days.map(\.provider)) {
            let saved = days.filter { $0.provider == provider && $0.isValid }.sorted { $0.intervalStart < $1.intervalStart }
            var observed = Array(repeating: 0, count: saved.count)
            var observedBillable = observed
            for event in events where event.provider == provider {
                var lower = 0, upper = saved.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if saved[middle].intervalStart <= event.timestamp { lower = middle + 1 } else { upper = middle }
                }
                let index = lower - 1
                guard saved.indices.contains(index), event.timestamp < saved[index].intervalEnd else { continue }
                observed[index] += event.inputTokens + event.outputTokens + event.cacheCreationTokens + event.cacheReadTokens
                observedBillable[index] += event.inputTokens + event.outputTokens
            }
            for (index, day) in saved.enumerated() {
                let remainder = max(0, day.tokensIncludingCache - observed[index])
                guard remainder > 0, let displayDay = day.displayDay(calendar: calendar) else { continue }
                let billable = min(remainder, max(0, day.inputPlusOutputTokens - observedBillable[index]))
                // A daily snapshot has no model or per-call timing. Preserve its original date and leave its API value unpriced.
                output.append(DailyTokenBucket(dayStart: displayDay, tokens: remainder, billableTokens: billable,
                                               dollars: 0, unpricedTokens: remainder, recoveredTokens: remainder))
            }
        }
        return output
    }
}
