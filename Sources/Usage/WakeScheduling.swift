import Foundation

/// Pure decisions for post-wake polling: recognizing the overdue catch-up
/// fire a repeating Timer delivers on wake, and whether waking warrants an
/// off-schedule refresh at all. Kept free of store/AppKit dependencies so
/// scripts/run-tests.sh can compile it standalone.
enum WakeScheduling {
    /// How late a repeating-timer fire must be before we call it a wake
    /// catch-up rather than run-loop jitter. Tolerance and a busy main
    /// thread account for seconds; only sleep accounts for minutes.
    static let overdueSlack: TimeInterval = 120

    /// How long after wake to hold the first poll. Long enough for Wi-Fi to
    /// re-associate and for the reconnect burst of every dormant Claude Code
    /// session — which shares /api/oauth/usage's sticky per-account limiter —
    /// to pass; short enough that the panel updates within the first minute
    /// of the user sitting down.
    static let graceDelay: TimeInterval = 60

    /// True when a repeating-timer fire arrives so far past its schedule that
    /// the machine must have slept through the fire date. The run loop
    /// delivers exactly one immediate catch-up fire on wake — probing then
    /// races the half-up network, the wake burst, and an access token that
    /// expired mid-sleep, which is how "rate limited"/"token expired" land
    /// right as the lid opens.
    static func isOverdueFire(now: Date, expected: Date?) -> Bool {
        guard let expected else { return false }
        return now.timeIntervalSince(expected) > overdueSlack
    }

    /// Whether a wake should schedule an off-schedule refresh. A lid flip
    /// after a short nap doesn't need one — the data is fresher than one poll
    /// interval, and refreshing every wake would undercut the 5-minute floor
    /// the presets enforce against Anthropic's limiter.
    static func shouldRefreshAfterWake(
        lastPoll: Date?, now: Date, pollInterval: TimeInterval
    ) -> Bool {
        guard let lastPoll else { return true }
        return now.timeIntervalSince(lastPoll) >= pollInterval
    }
}
