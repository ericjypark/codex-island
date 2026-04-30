import Foundation
import Combine

/// Singleton equivalent of `UsageStore` for the cost screen. Reads local
/// session logs (Claude Code + Codex CLI), aggregates today + month-to-date
/// spend per provider, and publishes the result for SwiftUI consumers.
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

    private static let cacheKey = "MacIsland.costCache.v1"
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?

    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    private init() {
        restoreFromCache()
    }

    func refresh() {
        // Per-provider gate so a slow Claude scan doesn't block a fast
        // Codex one (and vice versa) on the next tick.
        if !claudeLoading {
            claudeLoading = true
            Task.detached(priority: .userInitiated) { [weak self] in
                let events = ClaudeLogReader.scan()
                let cost = Self.summarize(events: events)
                await self?.commitClaude(cost)
            }
        }
        if !codexLoading {
            codexLoading = true
            Task.detached(priority: .userInitiated) { [weak self] in
                let events = CodexLogReader.scan()
                let cost = Self.summarize(events: events)
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

    /// Pure aggregation. Lives as a static so the detached refresh task can
    /// call it without touching @MainActor-isolated state.
    nonisolated private static func summarize(events: [TokenEvent]) -> ProviderCost {
        let todayEvents = CostBucketing.eventsForToday(events)
        let monthEvents = CostBucketing.eventsForMonthToDate(events)

        let todaySum = todayEvents.reduce(0.0) { $0 + Pricing.cost(for: $1) }
        let monthSum = monthEvents.reduce(0.0) { $0 + Pricing.cost(for: $1) }

        return ProviderCost(
            today: CostWindow(
                dollars: todaySum,
                label: "today",
                resetCaption: CostBucketing.todayResetCaption,
                error: nil
            ),
            month: CostWindow(
                dollars: monthSum,
                label: CostBucketing.currentMonthLabel(),
                resetCaption: CostBucketing.monthResetCaption(),
                error: nil
            )
        )
    }

    // MARK: - Cache

    /// Snapshot the four key totals + the last refresh time. Labels and
    /// reset captions are recomputed at restore time (current month, current
    /// reset countdown) so the cached numbers always sit under fresh chrome.
    private func persist() {
        let snap: [String: Any] = [
            "claudeToday": claude.today.dollars,
            "claudeMonth": claude.month.dollars,
            "codexToday": codex.today.dollars,
            "codexMonth": codex.month.dollars,
            "lastUpdated": lastUpdated?.timeIntervalSinceReferenceDate ?? 0,
        ]
        UserDefaults.standard.set(snap, forKey: Self.cacheKey)
    }

    private func restoreFromCache() {
        guard let snap = UserDefaults.standard.dictionary(forKey: Self.cacheKey) else { return }
        let claudeToday = snap["claudeToday"] as? Double ?? 0
        let claudeMonth = snap["claudeMonth"] as? Double ?? 0
        let codexToday = snap["codexToday"] as? Double ?? 0
        let codexMonth = snap["codexMonth"] as? Double ?? 0

        self.claude = ProviderCost(
            today: CostWindow(dollars: claudeToday, label: "today",
                              resetCaption: CostBucketing.todayResetCaption, error: nil),
            month: CostWindow(dollars: claudeMonth, label: CostBucketing.currentMonthLabel(),
                              resetCaption: CostBucketing.monthResetCaption(), error: nil)
        )
        self.codex = ProviderCost(
            today: CostWindow(dollars: codexToday, label: "today",
                              resetCaption: CostBucketing.todayResetCaption, error: nil),
            month: CostWindow(dollars: codexMonth, label: CostBucketing.currentMonthLabel(),
                              resetCaption: CostBucketing.monthResetCaption(), error: nil)
        )
        if let ts = snap["lastUpdated"] as? Double, ts > 0 {
            self.lastUpdated = Date(timeIntervalSinceReferenceDate: ts)
        }
    }
}
