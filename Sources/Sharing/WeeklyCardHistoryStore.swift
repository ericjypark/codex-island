import Foundation
import Combine

@MainActor
final class WeeklyCardHistoryStore: ObservableObject {
    @Published private(set) var buckets: [IslandProvider: [DailyTokenBucket]]?
    @Published private(set) var isLoading = false
    @Published private(set) var partialProviders = Set<IslandProvider>()
    @Published private(set) var saveErrors: [IslandProvider: String] = [:]

    func loadIfNeeded() {
        if buckets == nil { refresh() }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let result = await Task.detached(priority: .utility) {
                let now = Date()
                let openCode = UsageLedger.shared.retain(OpenCodeLogReader.scan(lookbackDays: nil),
                                                        source: .openCode, now: now, observedAt: now)
                var buckets: [IslandProvider: [DailyTokenBucket]] = [:]
                var partial = Set<IslandProvider>()
                var saveErrors: [IslandProvider: String] = [:]
                let claude = UsageLedger.shared.retain(ClaudeLogReader.scan(lookbackDays: nil),
                                                       source: .claude, now: now, observedAt: now)
                let codex = UsageLedger.shared.retain(CodexLogReader.scan(lookbackDays: nil),
                                                      source: .codex, now: now, observedAt: now)
                buckets[.claude] = CostSummary.summarize(
                    events: claude.events + openCode.events.filter { $0.provider == .claude },
                    now: now, includeAllHistory: true, historicalDays: claude.historicalDays
                ).dailyTokens
                buckets[.codex] = CostSummary.summarize(
                    events: codex.events + openCode.events.filter { $0.provider == .codex },
                    now: now, includeAllHistory: true, historicalDays: codex.historicalDays
                ).dailyTokens
                saveErrors[.claude] = claude.saveError ?? openCode.saveError
                saveErrors[.codex] = codex.saveError ?? openCode.saveError
                for provider in [IslandProvider.antigravity, .grok] {
                    let scan = provider == .antigravity
                        ? AntigravityLogReader.scan(lookbackDays: nil, now: now)
                        : GrokLogReader.scan(lookbackDays: nil, now: now)
                    let saved = UsageLedger.shared.retain(scan.events,
                                                          source: provider == .antigravity ? .antigravity : .grok,
                                                          now: now, observedAt: now)
                    buckets[provider] = CostSummary.summarize(events: saved.events, now: now, includeAllHistory: true,
                                                            historicalDays: saved.historicalDays).dailyTokens
                    saveErrors[provider] = saved.saveError
                    if scan.notice?.hasPrefix("Some") == true { partial.insert(provider) }
                }
                return (buckets, partial, saveErrors)
            }.value
            buckets = result.0
            partialProviders = result.1
            saveErrors = result.2
            isLoading = false
        }
    }
}
