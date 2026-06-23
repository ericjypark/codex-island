import Foundation
import Combine

/// Singleton equivalent of `UsageStore` for the cost screen. Reads local
/// session logs (Claude Code + Codex CLI), aggregates today + month-to-date
/// spend plus overview token history per provider, and publishes the result
/// for SwiftUI consumers.
///
/// Per-provider loading flags drive parallel scans that commit independently
/// — Codex (small) appears within ~50ms while Claude (often 20k+ events)
/// continues to scan in the background. Last-known totals are cached to
/// UserDefaults so the first hover after launch shows yesterday's snapshot
/// instantly rather than zeros.
@MainActor
final class CostStore: ObservableObject {
    static let shared = CostStore()

    @Published var claude: ProviderCost = .empty
    @Published var codex: ProviderCost = .empty
    @Published var claudeLoading = false
    @Published var codexLoading = false
    @Published var lastUpdated: Date?

    var loading: Bool { claudeLoading || codexLoading }

    private static let cacheKey = "MacIsland.costCache.v7"
    private static let cacheEncoder = JSONEncoder()
    private static let cacheDecoder = JSONDecoder()
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?

    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    private init() {
        if AppEnvironment.isDemo {
            loadDemoData()
            return
        }
        restoreFromCache()
    }

    func refresh() {
        // Demo mode: skip log scanning, inject hand-tuned numbers that
        // tell a "user extracts more value than the $200 subscription"
        // story. Never persists, so real cache is preserved.
        if AppEnvironment.isDemo {
            loadDemoData()
            return
        }
        let days = CostSummary.yearHistoryDays()
        // Only scan OpenCode when at least one provider will consume
        // the result; avoids wasted I/O when both are already loading.
        let openCodeTask: Task<[TokenEvent], Never>?
        if !claudeLoading || !codexLoading {
            openCodeTask = Task.detached(priority: .userInitiated) {
                OpenCodeLogReader.scan(lookbackDays: days)
            }
        } else {
            openCodeTask = nil
        }
        // Per-provider gate so a slow Claude scan doesn't block a fast
        // Codex one (and vice versa) on the next tick.
        if !claudeLoading {
            claudeLoading = true
            Task.detached(priority: .userInitiated) { [weak self] in
                let openCodeEvents = await openCodeTask?.value ?? []
                let events = ClaudeLogReader.scan(lookbackDays: days)
                    + openCodeEvents.filter { $0.provider == .claude }
                let cost = CostSummary.summarize(events: events)
                await self?.commitClaude(cost)
            }
        }
        if !codexLoading {
            codexLoading = true
            Task.detached(priority: .userInitiated) { [weak self] in
                let openCodeEvents = await openCodeTask?.value ?? []
                let events = CodexLogReader.scan(lookbackDays: days)
                    + openCodeEvents.filter { $0.provider == .codex }
                let cost = CostSummary.summarize(events: events)
                await self?.commitCodex(cost)
            }
        }
    }

    private func commitClaude(_ cost: ProviderCost) {
        self.claude = cost
        self.claudeLoading = false
        self.lastUpdated = Date()
        persist()
    }

    private func commitCodex(_ cost: ProviderCost) {
        self.codex = cost
        self.codexLoading = false
        self.lastUpdated = Date()
        persist()
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refresh()
        armTimer()
        intervalCancellable = RefreshIntervalStore.shared.$seconds
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.armTimer() }
            }
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
        intervalCancellable?.cancel()
        intervalCancellable = nil
    }

    private func armTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Demo data for screen recordings, derived from the maintainer's real
    /// April 2026 logs aggregated via /tmp/april_dump.py. "Today" mirrors
    /// April 29 (a balanced active day across both providers); monthly
    /// totals + cumulative series are the actual full-April aggregates.
    /// Month label hardcoded to "April" so the data and the header agree
    /// even when the real system clock has rolled into May.
    private func loadDemoData() {
        // Claude: morning-warrior pattern — early start, big morning push,
        // lunch plateau, afternoon resurge, tapering evening. Multi-peak.
        // Monthly is the real April aggregate (already bursty/stepped).
        // Demo billable tokens are ~10% of total — the typical ratio when
        // cache reads dominate Claude Code workflows.
        self.claude = ProviderCost(
            today: CostWindow(
                dollars: 146.61, tokens: 211_240_000, billableTokens: 21_124_000,
                series: [0, 0, 0, 0, 0, 0, 0.8, 4.5, 18.2, 38.7, 58.3, 71.4, 73.8, 76.5, 87.2, 102.8, 117.4, 128.6, 135.2, 140.7, 144.5, 146.0, 146.4, 146.61],
                label: "Today", error: nil, unknownModels: []
            ),
            month: CostWindow(
                dollars: 1510.80, tokens: 2_170_970_947, billableTokens: 217_097_094,
                series: [4.32, 11.52, 41.47, 47.80, 67.99, 88.68, 208.14, 249.74, 327.76, 406.09, 438.15, 462.90, 477.83, 576.16, 618.03, 689.91, 710.34, 805.93, 851.29, 866.94, 866.94, 902.46, 951.91, 1010.17, 1073.80, 1128.92, 1182.69, 1219.69, 1366.31, 1510.80],
                label: "April", error: nil, unknownModels: []
            ),
            dailyTokens: Self.demoDailyBuckets([
                24, 31, 128, 44, 82, 76, 310, 122, 218, 236,
                98, 64, 47, 286, 140, 205, 59, 276, 119, 48,
                0, 86, 136, 154, 168, 148, 132, 94, 402, 211,
            ], millionScale: 1_000_000)
        )
        // Codex: evening-person pattern — flat all morning, light midday,
        // explodes 6pm-11pm. Single big surge contrasts Claude's two-peak day.
        // Monthly is a smooth accelerating curve (linearly-rising daily
        // deltas, $12 → $77/day) — visually opposite to Claude's stepped jumps.
        self.codex = ProviderCost(
            today: CostWindow(
                dollars: 136.50, tokens: 164_120_000, billableTokens: 32_824_000,
                series: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2.4, 6.8, 11.5, 17.2, 22.8, 28.4, 38.5, 51.7, 67.4, 84.6, 102.3, 118.8, 130.4, 136.50],
                label: "Today", error: nil, unknownModels: []
            ),
            month: CostWindow(
                dollars: 1342.60, tokens: 1_614_300_000, billableTokens: 322_860_000,
                series: [12.20, 26.70, 43.50, 62.40, 83.70, 107.10, 132.80, 160.70, 190.90, 223.30, 257.90, 294.80, 333.90, 375.30, 418.90, 464.70, 512.80, 563.10, 615.70, 670.50, 727.50, 786.80, 848.30, 912.00, 978.00, 1046.20, 1116.70, 1189.40, 1264.30, 1342.60],
                label: "April", error: nil, unknownModels: []
            ),
            dailyTokens: Self.demoDailyBuckets([
                12, 18, 24, 29, 37, 42, 51, 59, 66, 74,
                83, 90, 99, 108, 117, 124, 136, 145, 157, 166,
                175, 188, 201, 214, 228, 239, 254, 268, 282, 164,
            ], millionScale: 1_000_000)
        )
        self.lastUpdated = Date()
    }

    private static func demoDailyBuckets(
        _ values: [Int],
        millionScale: Int
    ) -> [DailyTokenBucket] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let days = CostSummary.yearHistoryDays()
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return (0..<days).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
            let value = values[offset % values.count]
            let tokens = value * millionScale
            return DailyTokenBucket(dayStart: day, tokens: tokens, billableTokens: tokens / 10)
        }
    }

    // MARK: - Cache

    /// Full snapshot of both providers encoded as JSON in a single key.
    /// `unknownModels` arrays default to empty when decoding a snapshot that
    /// pre-dates the field, so the cache survives the schema change without
    /// a key bump or a forced rescan.
    private struct CacheSnapshot: Codable {
        var claudeToday: Double
        var claudeMonth: Double
        var codexToday: Double
        var codexMonth: Double
        var claudeTodayTokens: Int
        var claudeMonthTokens: Int
        var codexTodayTokens: Int
        var codexMonthTokens: Int
        var claudeTodayBillable: Int = 0
        var claudeMonthBillable: Int = 0
        var codexTodayBillable: Int = 0
        var codexMonthBillable: Int = 0
        var claudeTodaySeries: [Double]
        var claudeMonthSeries: [Double]
        var codexTodaySeries: [Double]
        var codexMonthSeries: [Double]
        var claudeTodayUnknown: [String] = []
        var claudeMonthUnknown: [String] = []
        var codexTodayUnknown: [String] = []
        var codexMonthUnknown: [String] = []
        var claudeDailyTokens: [DailyTokenBucket]
        var codexDailyTokens: [DailyTokenBucket]
        var lastUpdated: Date?
    }

    /// Encodes the full snapshot as a single Data value — 1 write vs. the
    /// previous 12-key dict, halving UserDefaults churn per refresh cycle.
    private func persist() {
        let snap = CacheSnapshot(
            claudeToday: claude.today.dollars,
            claudeMonth: claude.month.dollars,
            codexToday: codex.today.dollars,
            codexMonth: codex.month.dollars,
            claudeTodayTokens: claude.today.tokens,
            claudeMonthTokens: claude.month.tokens,
            codexTodayTokens: codex.today.tokens,
            codexMonthTokens: codex.month.tokens,
            claudeTodayBillable: claude.today.billableTokens,
            claudeMonthBillable: claude.month.billableTokens,
            codexTodayBillable: codex.today.billableTokens,
            codexMonthBillable: codex.month.billableTokens,
            claudeTodaySeries: claude.today.series,
            claudeMonthSeries: claude.month.series,
            codexTodaySeries: codex.today.series,
            codexMonthSeries: codex.month.series,
            claudeTodayUnknown: claude.today.unknownModels,
            claudeMonthUnknown: claude.month.unknownModels,
            codexTodayUnknown: codex.today.unknownModels,
            codexMonthUnknown: codex.month.unknownModels,
            claudeDailyTokens: claude.dailyTokens,
            codexDailyTokens: codex.dailyTokens,
            lastUpdated: lastUpdated
        )
        if let data = try? Self.cacheEncoder.encode(snap) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func restoreFromCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let snap = try? Self.cacheDecoder.decode(CacheSnapshot.self, from: data)
        else { return }

        self.claude = ProviderCost(
            today: CostWindow(dollars: snap.claudeToday, tokens: snap.claudeTodayTokens,
                              billableTokens: snap.claudeTodayBillable,
                              series: snap.claudeTodaySeries, label: "Today", error: nil,
                              unknownModels: snap.claudeTodayUnknown),
            month: CostWindow(dollars: snap.claudeMonth, tokens: snap.claudeMonthTokens,
                              billableTokens: snap.claudeMonthBillable,
                              series: snap.claudeMonthSeries,
                              label: CostBucketing.currentMonthLabel(), error: nil,
                              unknownModels: snap.claudeMonthUnknown),
            dailyTokens: snap.claudeDailyTokens
        )
        self.codex = ProviderCost(
            today: CostWindow(dollars: snap.codexToday, tokens: snap.codexTodayTokens,
                              billableTokens: snap.codexTodayBillable,
                              series: snap.codexTodaySeries, label: "Today", error: nil,
                              unknownModels: snap.codexTodayUnknown),
            month: CostWindow(dollars: snap.codexMonth, tokens: snap.codexMonthTokens,
                              billableTokens: snap.codexMonthBillable,
                              series: snap.codexMonthSeries,
                              label: CostBucketing.currentMonthLabel(), error: nil,
                              unknownModels: snap.codexMonthUnknown),
            dailyTokens: snap.codexDailyTokens
        )
        self.lastUpdated = snap.lastUpdated
    }
}
