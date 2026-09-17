import AppKit
import Foundation
import Combine
import Network

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    private init() {}

    @Published var claude: AppUsage = .empty
    @Published var codex: AppUsage = .empty
    @Published var codexResetCredits: CodexResetCredits = .empty
    @Published var lastUpdated: Date?
    @Published var loading = false
    /// Set while a `claude auth login` flow is in progress (spawned + still
    /// polling for the keychain to update). The UI hides the re-auth button
    /// during this window so users don't double-tap and spawn duplicate CLI
    /// processes; the click ends up no-ops anyway because the spawn check
    /// gates on this.
    @Published var claudeReauthInProgress = false

    private var refreshRequestedAfterSelection = false
    private var refreshTask: Task<Void, Never>?
    private var reauthPollTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var intervalCancellable: AnyCancellable?
    private var netMonitor: NWPathMonitor?
    private let netQueue = DispatchQueue(label: "UsageStore.network")
    private var lastNetStatus: NWPath.Status?
    /// When the armed timer is scheduled to fire next. A fire that lands far
    /// past this is the catch-up fire of a wake (see `WakeScheduling`).
    private var nextExpectedFire: Date?
    /// End of the post-wake grace window. While set and in the future, the
    /// network monitor's transition refresh stands down — the deferred wake
    /// refresh owns the first post-wake probe.
    private var wakeGraceUntil: Date?
    private var wakeRefreshTask: Task<Void, Never>?
    private var credWatchTask: Task<Void, Never>?
    private var deferredClaudeRefreshTask: Task<Void, Never>?
    private var cooldownRetryTask: Task<Void, Never>?
    private var sleepWakeObservers: [NSObjectProtocol] = []
    /// One CLI refresh ping per expiry episode: armed when the expired-token
    /// failure first lands, reset by the next successful Claude fetch. If the
    /// ping can't fix the store (no CLI, revoked refresh token), the flag
    /// stays set so we never spawn again — the re-auth panel remains the
    /// fallback.
    private var tokenRefreshPingAttempted = false

    /// Anthropic's /api/oauth/usage is aggressively rate-limited per token.
    /// `RefreshIntervalStore` enforces a 5-minute floor (300/900/1800).
    private var pollInterval: TimeInterval {
        TimeInterval(RefreshIntervalStore.shared.seconds)
    }

    /// The /api/oauth/usage limiter is sticky once tripped: it returns 429
    /// with `retry-after: 0` until the account has gone quiet for a while
    /// (anthropics/claude-code#30930), so polling through it never recovers.
    /// After a rate-limited fetch, skip Claude fetches for this long.
    /// Deliberately in-memory only — a quit+relaunch retries immediately.
    private static let rateLimitCooldown: TimeInterval = 900
    private var claudeCooldown = ClaudeUsageCooldown()
    private var claudeRequestGate = ClaudeRequestGate()

    func refreshForSelectionChange() {
        if loading {
            updateCredentialStoreWatch(
                claudeSelected: ProviderVisibilityStore.shared.selected.contains(.claude))
            refreshRequestedAfterSelection = true
        } else {
            refresh()
        }
    }

    func refresh() {
        ProviderConnectionStore.shared.refreshSelected()
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
            self.codexResetCredits = CodexResetCredits(
                availableCount: 2,
                credits: [
                    CodexResetCredit(
                        id: "demo-reset-1",
                        status: "available",
                        expiresAt: now.addingTimeInterval(3 * 86400 + 4 * 3600),
                        title: "One free rate limit reset",
                        description: "Thanks for using Codex! You've been granted one free rate limit reset."
                    ),
                    CodexResetCredit(
                        id: "demo-reset-2",
                        status: "available",
                        expiresAt: now.addingTimeInterval(9 * 86400 + 3600),
                        title: "One free rate limit reset",
                        description: "Thanks for using Codex! You've been granted one free rate limit reset."
                    )
                ]
            )
            self.lastUpdated = now
            return
        }

        let selection = ProviderVisibilityStore.shared.selected
        updateCredentialStoreWatch(claudeSelected: selection.contains(.claude))

        loading = true
        refreshTask?.cancel()
        refreshTask = Task {
            defer {
                self.loading = false
                if self.refreshRequestedAfterSelection {
                    self.refreshRequestedAfterSelection = false
                    self.refresh()
                }
            }
            async let codexResult: AppUsage? = selection.contains(.codex) ? UsageFetcher.fetchCodex() : nil
            async let codexResetCreditsResult = selection.contains(.codex) ? UsageFetcher.fetchCodexResetCredits() : nil
            let coolingDown = claudeCooldown.isActive(at: Date())
            var cl: AppUsage?
            if !coolingDown && selection.contains(.claude) {
                cl = await fetchClaudeIfAllowed()
            }
            let c = await codexResult
            let codexResetCredits = await codexResetCreditsResult

            // Cancellation = network monitor saw the path come up while we
            // were mid-flight on a dead one. The fetched values are the
            // dead-path errors — drop them so the supersedes refresh
            // doesn't have a brief "cancelled" caption flash to overwrite.
            if Task.isCancelled {
                self.loading = false
                return
            }

            let now = Date()

            // A failed poll must neither blank the panel nor hide the
            // failure. `merge` keeps each window's last real reading and
            // attaches the new error to it, so the tile shows a true number
            // captioned with what went wrong. A window with nothing to carry
            // stays at `hasReading == false`, which the UI renders as "—"
            // instead of the fabricated 0% it used to show.
            // Post-merge refill: a transient failure landing on windows with
            // nothing to carry (post-wake: the expiry wipe cleared them, the
            // recovered token's first probe hit the wake-burst 429) blanked
            // the tiles for the whole 15-min cooldown. History still has the
            // pre-sleep readings — show them under the failure caption, the
            // same stale-but-true contract as the launch seed.
            if let c {
                let priorCodex = self.codex
                self.codex = UsageStore.seeded(
                    AppUsage.merged(fetched: c, retaining: priorCodex, at: now),
                    prior: priorCodex, provider: .codex, fillUnreported: false)
            }
            if let cl {
                if UsageStore.isRateLimited(cl) {
                    self.claudeCooldown.arm(now: Date(), duration: UsageStore.rateLimitCooldown)
                    NSLog("CodexIsland: Claude usage rate-limited; skipping Claude fetches for %.0fs", UsageStore.rateLimitCooldown)
                    self.scheduleCooldownRetry()
                } else {
                    self.claudeCooldown.clear()
                }
                // A terminal auth failure (expired token / missing scope)
                // REPLACES the retained reading rather than carrying it: the
                // token can never refresh those numbers again, and
                // `ChartsBlock` keys the re-auth prompt off the error-only
                // shape. Transient errors (429/network) still carry forward.
                let terminal = ClaudeCredentials.isTerminalAuthFailure(cl)
                // Terminal failures keep the bare error-only shape — the
                // re-auth panel keys off it, and seeding numbers under it
                // would suppress the prompt. Transient failures refill like
                // codex above.
                let priorClaude = self.claude
                self.claude = terminal
                    ? cl
                    : UsageStore.seeded(
                        AppUsage.merged(fetched: cl, retaining: priorClaude, at: now),
                        prior: priorClaude, provider: .claude, fillUnreported: false)
                if terminal {
                    // The one terminal failure a CLI ping can fix: an expired
                    // token in a store nothing else maintains (desktop-app
                    // Claude Code brings its own host-refreshed token and
                    // never writes the CLI store). The ping's writeback is
                    // what the credential watch then catches.
                    if ClaudeCredentials.shouldSpawnRefreshPing(
                        for: cl,
                        alreadyAttempted: self.tokenRefreshPingAttempted,
                        reauthInProgress: self.claudeReauthInProgress
                    ) {
                        self.tokenRefreshPingAttempted = true
                        ClaudeCredentials.spawnTokenRefreshPing()
                    }
                } else if cl.fiveHour.error == nil || cl.weekly.error == nil {
                    self.tokenRefreshPingAttempted = false
                }
            }
            if let codexResetCredits {
                self.codexResetCredits = codexResetCredits
            }

            // Record this poll's readings so the SparkChart can plot real
            // history. `record` keeps only non-errored windows, so a failed
            // or rate-limited fetch leaves a gap instead of a flat fake line.
            if let c { UsageHistoryStore.shared.record(provider: .codex, usage: c, at: now) }
            if let cl { UsageHistoryStore.shared.record(provider: .claude, usage: cl, at: now) }
            self.lastUpdated = now
            self.loading = false
        }
    }

    /// Prime the panel from persisted history before the first fetch lands.
    ///
    /// `UsageHistoryStore` survives relaunch, so a cold start that hits a
    /// failing endpoint can still show the user's last real numbers. This is
    /// what makes the sticky `/api/oauth/usage` 429 survivable: that penalty
    /// outlives an app restart (anthropics/claude-code#30930), so without a
    /// seed the first failed fetch has nothing to carry and every tile falls
    /// to "—" for the whole cooldown.
    private func seedFromHistory() {
        claude = UsageStore.seeded(claude, provider: .claude, fillUnreported: true)
        codex = UsageStore.seeded(codex, provider: .codex, fillUnreported: true)
    }

    /// `fillUnreported`: at launch the passive "no data" sentinel just means
    /// "nothing fetched yet", so history may paint it. After a fetch it
    /// means the provider omitted the window from a parsed response
    /// (single-window Codex plans) — refilling would resurrect exactly the
    /// frozen mislabeled reading the span-routing fix displaces, so the
    /// mid-run refill path leaves those alone. That check runs against the
    /// PRIOR window too: a transient failure replaces the sentinel's caption
    /// with its own, and judging only the merged shape would re-open the
    /// refill door on every failed poll.
    private static func seeded(_ current: AppUsage, prior: AppUsage? = nil,
                               provider: AlertEngine.Provider,
                               fillUnreported: Bool) -> AppUsage {
        func fill(_ kind: UsageWindow, _ existing: WindowUsage,
                  _ priorWindow: WindowUsage?) -> WindowUsage {
            if let reported = current.reportedWindows, !reported.contains(kind) { return .unknown }
            guard !existing.hasReading else { return existing }
            if !fillUnreported {
                if existing.isUnreported { return existing }
                if let priorWindow, priorWindow.isUnreported { return existing }
            }
            guard let sample = UsageHistoryStore.shared.latestReading(
                provider: provider, window: kind)
            else { return existing }
            // No resetAt: the sample never carried one, and inventing a
            // countdown from a stored percentage would be a second fiction.
            return WindowUsage(usedPercent: sample.used, resetAt: nil, error: existing.error)
        }
        return AppUsage(
            fiveHour: fill(.fiveHour, current.fiveHour, prior?.fiveHour),
            weekly: fill(.weekly, current.weekly, prior?.weekly),
            plan: current.plan,
            reportedWindows: current.reportedWindows
        )
    }


    /// True when the fetch resolved to the rate-limited error (both windows
    /// carry the same message — see `UsageFetcher.errorPair`).
    private static func isRateLimited(_ u: AppUsage) -> Bool {
        u.fiveHour.error == ClaudeCredentials.rateLimitedMessage
            && u.weekly.error == ClaudeCredentials.rateLimitedMessage
    }

    /// Replace current usage values with hand-tuned percentages so the
    /// alert engine's pulse + tint behavior can be exercised without
    /// waiting for a real provider crossing. Auto-refresh continues — the
    /// next scheduled poll will overwrite these values with real data.
    /// Each call uses fresh `resetAt` timestamps so the alert engine
    /// treats it as a new reset window and re-evaluates crossings.
    func injectPreviewUsage(claudeFiveHour: Double, codexFiveHour: Double) {
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
        guard ClaudeCredentials.spawnReauth() else { return }
        claudeReauthInProgress = true
        reauthPollTask?.cancel()
        reauthPollTask = Task { [weak self] in
            // ~2 minutes total — generous enough that even a slow OAuth
            // round-trip (browser cold start, SSO redirect, 2FA prompt)
            // resolves in time, short enough to not strand the UI.
            var baseline = ClaudeCredentials.credentialStoreFingerprint()
            var sawStoreWrite = false
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                // Wait for `claude auth login` to actually write the new
                // credentials before paying the secret read: the fingerprint
                // is metadata-only (never prompts), while clearing the cache
                // does a full keychain read on the next fetch — doing that
                // on every 5s tick was up to 24 ACL prompts per re-auth on
                // machines without a durable "Always Allow" grant. After the
                // first observed write, keep RETRYING from the cached
                // credential (zero extra secret reads) so one transient
                // network failure doesn't strand the button on "waiting for
                // browser…" until the deadline; the cache is cleared again
                // only when the store changes again.
                let current = ClaudeCredentials.credentialStoreFingerprint()
                if current != baseline {
                    baseline = current
                    sawStoreWrite = true
                    ClaudeCredentials.clearCache()
                }
                guard sawStoreWrite else { continue }
                guard let cl = await self?.fetchClaudeIfAllowed() else { continue }
                if Task.isCancelled { return }
                // The usage limiter is sticky once tripped (see
                // rateLimitCooldown) — retrying every 5s only feeds it. Bail
                // and let the normal poll's cooldown machinery recover.
                if cl.fiveHour.error == ClaudeCredentials.rateLimitedMessage { break }
                if cl.fiveHour.error == nil || cl.weekly.error == nil {
                    await MainActor.run {
                        self?.claude = cl
                        self?.lastUpdated = Date()
                        self?.claudeReauthInProgress = false
                        // This poll owned the store write — retire the
                        // credential watch with its stale baseline, then
                        // restart it from the new store state.
                        self?.credWatchTask?.cancel()
                        self?.credWatchTask = nil
                        self?.updateCredentialStoreWatch(
                            claudeSelected: ProviderVisibilityStore.shared.selected.contains(.claude))
                        self?.tokenRefreshPingAttempted = false
                    }
                    return
                }
            }
            await MainActor.run { self?.claudeReauthInProgress = false }
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        seedFromHistory()
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
        startNetworkMonitor()
        startSleepWakeObservers()
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
        nextExpectedFire = nil
        intervalCancellable?.cancel()
        intervalCancellable = nil
        netMonitor?.cancel()
        netMonitor = nil
        lastNetStatus = nil
        let wsCenter = NSWorkspace.shared.notificationCenter
        sleepWakeObservers.forEach { wsCenter.removeObserver($0) }
        sleepWakeObservers = []
        wakeRefreshTask?.cancel()
        wakeRefreshTask = nil
        wakeGraceUntil = nil
        credWatchTask?.cancel()
        credWatchTask = nil
        deferredClaudeRefreshTask?.cancel()
        deferredClaudeRefreshTask = nil
        cooldownRetryTask?.cancel()
        cooldownRetryTask = nil
    }

    private func armTimer() {
        pollTimer?.invalidate()
        nextExpectedFire = Date().addingTimeInterval(pollInterval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.timerFired() }
        }
    }

    /// A repeating timer that slept through its fire date delivers one
    /// immediate catch-up fire on wake — the exact moment the network is
    /// still associating, every dormant Claude Code session's reconnect
    /// traffic is bursting against the shared /api/oauth/usage limiter, and
    /// the access token may have expired mid-sleep. Probing then is how
    /// "rate limited" (sticky, arms a 15-min cooldown) and "token expired"
    /// land right as the lid opens. Recognize the overdue fire and defer it
    /// past the burst instead of burning it.
    private func timerFired() {
        if WakeScheduling.isOverdueFire(now: Date(), expected: nextExpectedFire) {
            armTimer()
            deferPostWakeRefresh()
        } else if let grace = wakeGraceUntil, Date() < grace {
            // A pending fire preserved across a short nap can land inside
            // the grace window — defer it like the catch-up fire instead of
            // probing the still-associating network.
            nextExpectedFire = Date().addingTimeInterval(pollInterval)
            deferPostWakeRefresh()
        } else {
            nextExpectedFire = Date().addingTimeInterval(pollInterval)
            refresh()
        }
    }

    /// `didWakeNotification` and the overdue-fire check overlap on long
    /// sleeps — whichever runs first wins and the other converges — but each
    /// also covers the other's gap: the notification handles wakes where no
    /// timer fire was pending, the overdue check handles a catch-up fire the
    /// run loop delivers before the notification.
    private func startSleepWakeObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        sleepWakeObservers = [
            wsCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Drop the in-flight and pending work: a request cut off
                    // by sleep finalizes at wake as a dead-socket error, and
                    // the cancellation guard in refresh() discards it.
                    self?.refreshTask?.cancel()
                    self?.wakeRefreshTask?.cancel()
                }
            },
            wsCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Re-arm only when the scheduled fire was slept through.
                    // A sub-interval nap keeps its pending cadence — an
                    // unconditional re-arm silently postponed the next poll
                    // by a full interval on every lid flip.
                    if self.nextExpectedFire.map({ Date() >= $0 }) ?? true {
                        self.armTimer()
                    }
                    self.deferPostWakeRefresh()
                }
            },
        ]
    }

    /// Schedule the first post-wake refresh after a grace delay, replacing
    /// any pending one. Skipped entirely after short naps — the data is
    /// fresher than one poll interval, and refreshing every lid flip would
    /// undercut the 5-minute floor. The freshness recheck inside the task
    /// also collapses the didWake/catch-up overlap into a single probe.
    private func deferPostWakeRefresh() {
        // The grace window arms on EVERY wake — even when no off-schedule
        // refresh is warranted — so the network monitor's transition refresh
        // (Wi-Fi re-associating seconds after the lid opens) never probes
        // into the wake burst either.
        wakeGraceUntil = Date().addingTimeInterval(WakeScheduling.graceDelay)
        guard WakeScheduling.shouldRefreshAfterWake(
            lastPoll: lastUpdated, now: Date(), pollInterval: pollInterval
        ) else { return }
        wakeRefreshTask?.cancel()
        wakeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(WakeScheduling.graceDelay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard WakeScheduling.shouldRefreshAfterWake(
                lastPoll: self.lastUpdated, now: Date(), pollInterval: self.pollInterval
            ) else { return }
            self.refreshTask?.cancel()
            await self.refreshTask?.value
            if !Task.isCancelled { self.refresh() }
        }
    }

    private func updateCredentialStoreWatch(claudeSelected: Bool) {
        let action = ClaudeCredentialWatchPolicy.action(
            claudeSelected: claudeSelected,
            watchRunning: credWatchTask != nil)
        switch action {
        case .start:
            // Capture the baseline before broad discovery so a store rewrite
            // cannot land between discovery and watcher creation.
            watchCredentialStore()
            ClaudeCredentials.refreshCredentialStoreTargets()
        case .keep:
            // Broad keychain discovery stays on the ordinary refresh path;
            // the 5-second watcher only queries these Claude item identities.
            ClaudeCredentials.refreshCredentialStoreTargets()
        case .stop:
            credWatchTask?.cancel()
            credWatchTask = nil
            deferredClaudeRefreshTask?.cancel()
            deferredClaudeRefreshTask = nil
        case .none:
            break
        }
    }

    /// Detect external credential changes promptly without turning metadata
    /// checks into network polling. The request is separately coalesced at the
    /// endpoint's five-minute minimum.
    private func watchCredentialStore() {
        guard credWatchTask == nil else { return }
        let watch = ClaudeCredentials.CredentialStoreWatch()
        credWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                guard let self else { return }
                // The in-app re-auth poll owns the flow while it runs —
                // reacting here too would double-probe the usage endpoint
                // on the same store write.
                if self.claudeReauthInProgress { continue }
                if watch.invalidateCachedCredentialsIfStoreChanged() {
                    self.claudeCooldown.clear()
                    self.cooldownRetryTask?.cancel()
                    self.cooldownRetryTask = nil
                    self.scheduleClaudeRefreshAtSafeBoundary()
                }
            }
            // Deliberately no cleanup on the cancelled path: cancellers nil
            // the property themselves, and nilling here would clobber a
            // successor watch's reference.
        }
    }

    private func fetchClaudeIfAllowed() async -> AppUsage? {
        guard claudeRequestGate.claim(at: Date()) else {
            scheduleClaudeRefreshAtSafeBoundary()
            return nil
        }
        // A timer or manual refresh reached the safe boundary first. It owns
        // the new credential fetch, so retire the deferred duplicate.
        deferredClaudeRefreshTask?.cancel()
        deferredClaudeRefreshTask = nil
        return await UsageFetcher.fetchClaude()
    }

    private func scheduleClaudeRefreshAtSafeBoundary() {
        deferredClaudeRefreshTask?.cancel()
        deferredClaudeRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let delay = self.claudeRequestGate.delayUntilAllowed(at: Date())
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                await self.waitOutWakeGrace()
                guard !Task.isCancelled,
                      ProviderVisibilityStore.shared.selected.contains(.claude) else { return }
                // A timer or manual refresh may have claimed the gate while
                // this task waited through wake grace.
                if self.claudeRequestGate.delayUntilAllowed(at: Date()) > 0 { continue }
                self.deferredClaudeRefreshTask = nil
                self.refreshTask?.cancel()
                await self.refreshTask?.value
                if !Task.isCancelled { self.refresh() }
                return
            }
        }
    }

    /// One-shot refresh just past the cooldown so "rate limited" clears at
    /// the earliest safe moment. Without it, recovery waits for the next
    /// timer tick to line up AFTER the cooldown — worst case
    /// interval + cooldown ≈ 45 min on the 30m preset.
    private func scheduleCooldownRetry() {
        cooldownRetryTask?.cancel()
        cooldownRetryTask = Task { [weak self] in
            let delay = UsageStore.rateLimitCooldown + 10
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.waitOutWakeGrace()
            guard !Task.isCancelled else { return }
            self.cooldownRetryTask = nil
            self.refreshTask?.cancel()
            await self.refreshTask?.value
            if !Task.isCancelled { self.refresh() }
        }
    }

    /// One-shot recovery tasks sleep on `Task.sleep`, whose deadline keeps
    /// elapsing through system sleep — so a pending retry can otherwise fire
    /// in the first post-wake seconds, probing the exact burst the wake
    /// grace exists to dodge (and its failed attempt would then satisfy the
    /// wake refresh's freshness check). Hold until the grace passes; loops
    /// in case another wake re-arms the grace mid-wait.
    private func waitOutWakeGrace() async {
        while let grace = wakeGraceUntil, !Task.isCancelled {
            let remaining = grace.timeIntervalSinceNow
            guard remaining > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
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
                // Post-wake, Wi-Fi re-associates within seconds — refreshing
                // on that transition would probe straight into the wake
                // burst. The deferred wake refresh owns the first probe.
                if let grace = self.wakeGraceUntil, Date() < grace { return }
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
