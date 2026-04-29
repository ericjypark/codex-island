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

    /// Anthropic's /api/oauth/usage is aggressively rate-limited per token.
    /// 30s polling burns the quota immediately; 5 min is plenty given that
    /// the data is window-based (5h / 7d) and changes slowly.
    private let pollInterval: TimeInterval = 300

    func refresh() {
        if loading { return }
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
