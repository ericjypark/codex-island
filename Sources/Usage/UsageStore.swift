import Foundation
import Combine
import Network

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    private init() {}

    @Published var claude: AppUsage = .empty
    @Published var codex: AppUsage = .empty
    @Published var gemini: AppUsage = .empty
    @Published var lastUpdated: Date?
    @Published var loading = false
    /// Set while a `claude auth login` flow is in progress (spawned + still
    /// polling for the keychain to update). The UI hides the re-auth button
    /// during this window so users don't double-tap and spawn duplicate CLI
    /// processes; the click ends up no-ops anyway because the spawn check
    /// gates on this.
    @Published var claudeReauthInProgress = false

    private var refreshTask: Task<Void, Never>?
    private var reauthPollTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?
    private var netMonitor: NWPathMonitor?
    private let netQueue = DispatchQueue(label: "UsageStore.network")
    private var lastNetStatus: NWPath.Status?

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
        if AppEnvironment.isDemo {
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
            async let geminiResult = UsageFetcher.fetchGemini()
            let c = await codexResult
            let cl = await claudeResult
            let g = await geminiResult

            // Cancellation = network monitor saw the path come up while we
            // were mid-flight on a dead one. The fetched values are the
            // dead-path errors — drop them so the supersedes refresh
            // doesn't have a brief "cancelled" caption flash to overwrite.
            if Task.isCancelled {
                self.loading = false
                return
            }

            // Don't clobber existing good values when a fetch returns an
            // all-error result. A transient 429 shouldn't blank the panel
            // back to "0%" — that's worse than slightly stale data. But if
            // the existing value is itself error-only (cold start sitting
            // on `.empty`, or a series of failures), let the new error
            // through — otherwise a single bad first fetch sticks "no data"
            // permanently even after the network recovers.
            if !UsageStore.isErrorOnly(c) || UsageStore.isErrorOnly(self.codex) {
                self.codex = c
            }
            if !UsageStore.isErrorOnly(cl) || UsageStore.isErrorOnly(self.claude) {
                self.claude = cl
            }
            if !UsageStore.isErrorOnly(g) || UsageStore.isErrorOnly(self.gemini) {
                self.gemini = g
            }
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

    /// Replace current usage values with hand-tuned percentages so the
    /// alert engine's pulse + tint behavior can be exercised without
    /// waiting for a real provider crossing. Auto-refresh continues — the
    /// next scheduled poll will overwrite these values with real data.
    /// Each call uses fresh `resetAt` timestamps so the alert engine
    /// treats it as a new reset window and re-evaluates crossings.
    func injectPreviewUsage(claudeFiveHour: Double, codexFiveHour: Double, geminiFiveHour: Double) {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(2 * 3600 + 14 * 60)
        let weeklyReset = now.addingTimeInterval(4 * 86400 + 6 * 3600)
        self.claude = AppUsage(
            fiveHour: WindowUsage(
                usedPercent: claudeFiveHour,
                resetAt: fiveHourReset,
                error: nil
            ),
            weekly: WindowUsage(
                usedPercent: 0.45,
                resetAt: weeklyReset,
                error: nil
            ),
            plan: claude.plan ?? "max"
        )
        self.codex = AppUsage(
            fiveHour: WindowUsage(
                usedPercent: codexFiveHour,
                resetAt: fiveHourReset,
                error: nil
            ),
            weekly: WindowUsage(
                usedPercent: 0.30,
                resetAt: weeklyReset,
                error: nil
            ),
            plan: codex.plan ?? "pro"
        )
        self.gemini = AppUsage(
            fiveHour: WindowUsage(
                usedPercent: geminiFiveHour,
                resetAt: fiveHourReset,
                error: nil
            ),
            weekly: WindowUsage(
                usedPercent: 0.15,
                resetAt: weeklyReset,
                error: nil
            ),
            plan: gemini.plan ?? "ultra"
        )
        self.lastUpdated = now
    }

    /// Spawn `claude auth login` and poll for the keychain to update.
    ///
    /// We can't `await` the OAuth flow directly — it happens in a separate
    /// process that owns a browser tab and a localhost listener — so we kick
    /// off retries every few seconds and stop as soon as one returns success
    /// (or after a generous deadline so the button doesn't stay disabled
    /// forever if the user closes the browser without completing).
    func reauthenticateClaude() {
        guard !claudeReauthInProgress else { return }
        guard UsageFetcher.spawnClaudeReauth() else { return }
        claudeReauthInProgress = true
        reauthPollTask?.cancel()
        reauthPollTask = Task { [weak self] in
            // ~2 minutes total — generous enough that even a slow OAuth
            // round-trip (browser cold start, SSO redirect, 2FA prompt)
            // resolves in time, short enough to not strand the UI.
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                let cl = await UsageFetcher.fetchClaude()
                if Task.isCancelled { return }
                if cl.fiveHour.error == nil || cl.weekly.error == nil {
                    await MainActor.run {
                        self?.claude = cl
                        self?.lastUpdated = Date()
                        self?.claudeReauthInProgress = false
                    }
                    return
                }
            }
            await MainActor.run { self?.claudeReauthInProgress = false }
        }
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
                guard let self else { return }
                Task { @MainActor in self.armTimer() }
            }
        startNetworkMonitor()
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
        intervalCancellable?.cancel()
        intervalCancellable = nil
        netMonitor?.cancel()
        netMonitor = nil
        lastNetStatus = nil
    }

    private func armTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    /// Trigger an immediate refresh whenever the network transitions from
    /// unsatisfied to satisfied — closes the launch-at-login race where
    /// Wi-Fi is still associating when our first refresh fires. Without
    /// this, the panel sits at the empty cold-start state until the next
    /// scheduled poll (5–30 minutes away). The initial path callback fires
    /// with the current state and is deliberately ignored (lastNetStatus
    /// starts nil) — startAutoRefresh's own refresh() already covers
    /// cold-start, and acting on the initial callback would double-fire.
    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let was = self.lastNetStatus
                self.lastNetStatus = path.status
                guard path.status == .satisfied,
                      let prior = was, prior != .satisfied else { return }
                // Cancel any in-flight refresh — its URLSession call was
                // started on the dead path and is going to return an
                // error. Wait for it to finalize so its loading=false
                // lands before we start the replacement, otherwise our
                // refresh() hits the `if loading { return }` guard.
                self.refreshTask?.cancel()
                await self.refreshTask?.value
                self.refresh()
            }
        }
        monitor.start(queue: netQueue)
        netMonitor = monitor
    }
}
