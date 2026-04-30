import Foundation
import Combine

/// Singleton equivalent of `UsageStore` for the cost screen. Reads local
/// session logs (Claude Code + Codex CLI), aggregates today + month-to-date
/// spend per provider, and publishes the result for SwiftUI consumers.
///
/// File IO lives on a background queue; only the published assignment hops
/// back to the main actor. Refresh cadence is the same `RefreshIntervalStore`
/// that gates the API-side `UsageStore`, since they share the same UI panel.
@MainActor
final class CostStore: ObservableObject {
    static let shared = CostStore()
    private init() {}

    @Published var claude: ProviderCost = .empty
    @Published var codex: ProviderCost = .empty
    @Published var lastUpdated: Date?
    @Published var loading = false

    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?

    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    func refresh() {
        if loading { return }
        loading = true
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            let claudeEvents = ClaudeLogReader.scan()
            let codexEvents = CodexLogReader.scan()
            let claudeCost = Self.summarize(events: claudeEvents)
            let codexCost = Self.summarize(events: codexEvents)
            await self?.commit(claude: claudeCost, codex: codexCost)
        }
    }

    private func commit(claude claudeCost: ProviderCost, codex codexCost: ProviderCost) {
        self.claude = claudeCost
        self.codex = codexCost
        self.lastUpdated = Date()
        self.loading = false
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
                cap: CostBucketing.todayCap,
                label: "today",
                resetCaption: CostBucketing.todayResetCaption,
                error: nil
            ),
            month: CostWindow(
                dollars: monthSum,
                cap: CostBucketing.monthCap,
                label: CostBucketing.currentMonthLabel(),
                resetCaption: CostBucketing.monthResetCaption(),
                error: nil
            )
        )
    }
}
