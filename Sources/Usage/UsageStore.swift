import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    private init() {}

    @Published var claude: AppUsage = .empty
    @Published var codex: AppUsage = .empty
    @Published var lastUpdated: Date?
    @Published var loading = false

    private var refreshTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?

    /// Anthropic's /api/oauth/usage is aggressively rate-limited per token.
    /// `RefreshIntervalStore` enforces a 5-minute floor (300/900/1800).
    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    func refresh() {
        if loading { return }
        // Demo mode for screen recordings: skip the network entirely and
        // inject hand-tuned values that read as "real, healthy heavy-user
        // data". Reset times are recomputed each refresh so the countdowns
        // tick down naturally on camera. Off by default — only fires when
        // CODEXISLAND_DEMO=1 is set in the launching env.
        if ProcessInfo.processInfo.environment["CODEXISLAND_DEMO"] == "1" {
            let now = Date()
            self.claude = AppUsage(
                fiveHour: WindowUsage(
                    usedPercent: 0.73,
                    resetAt: now.addingTimeInterval(1 * 3600 + 47 * 60),
                    error: nil
                ),
                weekly: WindowUsage(
                    usedPercent: 0.81,
                    resetAt: now.addingTimeInterval(4 * 86400 + 11 * 3600),
                    error: nil
                ),
                plan: "max"
            )
            self.codex = AppUsage(
                fiveHour: WindowUsage(
                    usedPercent: 0.67,
                    resetAt: now.addingTimeInterval(2 * 3600 + 23 * 60),
                    error: nil
                ),
                weekly: WindowUsage(
                    usedPercent: 0.76,
                    resetAt: now.addingTimeInterval(4 * 86400 + 18 * 3600),
                    error: nil
                ),
                plan: "pro"
            )
            self.lastUpdated = now
            return
        }

        loading = true
        refreshTask?.cancel()
        refreshTask = Task {
            async let codexResult = UsageFetcher.fetchCodex()
            async let claudeResult = UsageFetcher.fetchClaude()
            let c = await codexResult
            let cl = await claudeResult

            // Don't clobber existing good values when a fetch returns an
            // all-error result. A transient 429 shouldn't blank the panel
            // back to "0%" — that's worse than slightly stale data.
            if !UsageStore.isErrorOnly(c) { self.codex = c }
            if !UsageStore.isErrorOnly(cl) { self.claude = cl }
            self.lastUpdated = Date()
            self.loading = false
        }
    }

    /// True when both windows have errors and zero values — nothing useful
    /// to show, so we keep whatever we had before.
    private static func isErrorOnly(_ u: AppUsage) -> Bool {
        u.fiveHour.error != nil && u.weekly.error != nil
            && u.fiveHour.usedPercent == 0 && u.weekly.usedPercent == 0
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refresh()
        armTimer()
        // Re-arm whenever the user changes the refresh interval. We
        // dropFirst() the initial @Published replay so we don't re-fire
        // refresh() on subscription.
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
}
