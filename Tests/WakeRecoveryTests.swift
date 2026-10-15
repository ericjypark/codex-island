import Foundation

/// Regression cover for the post-wake false alarms: "rate limited" /
/// "token expired" landing right as the lid opens and outliving their cause
/// (issue #35's stuck caption is the public sighting).
///
/// Two layers get locked down:
///  - `WakeScheduling`: recognizing the overdue catch-up fire a repeating
///    Timer delivers on wake, and skipping the off-schedule wake refresh
///    when the data is still fresh.
///  - The state walk that produces the blank "— rate limited" pair: a long
///    sleep expires the 5h window's carry (its resetAt passed), a terminal
///    auth failure wipes both windows, and every later 429 then has nothing
///    to carry — which is why wake needs its own deferral + recovery paths.
@main
struct WakeRecoveryTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    static let now = Date(timeIntervalSince1970: 1_784_000_000)

    /// The exact shape `UsageFetcher.errorPair` builds for a failed fetch.
    static func errored(_ message: String) -> WindowUsage {
        WindowUsage(usedPercent: 0, resetAt: nil, error: message)
    }

    static func reading(_ pct: Double, resetIn: TimeInterval? = nil) -> WindowUsage {
        WindowUsage(
            usedPercent: pct, resetAt: resetIn.map { now.addingTimeInterval($0) }, error: nil
        )
    }

    static func pair(_ five: WindowUsage, _ week: WindowUsage) -> AppUsage {
        AppUsage(fiveHour: five, weekly: week)
    }

    static func main() {
        // MARK: overdue-fire detection — the wake catch-up vs ordinary jitter

        let expected = now
        expect(
            !WakeScheduling.isOverdueFire(now: now, expected: expected),
            "an on-time fire is not overdue"
        )
        expect(
            !WakeScheduling.isOverdueFire(now: now.addingTimeInterval(30), expected: expected),
            "30s of run-loop jitter is not overdue"
        )
        expect(
            WakeScheduling.isOverdueFire(now: now.addingTimeInterval(121), expected: expected),
            "past the slack the fire is the wake catch-up"
        )
        expect(
            WakeScheduling.isOverdueFire(now: now.addingTimeInterval(6 * 3600), expected: expected),
            "an hours-late fire is the wake catch-up"
        )
        expect(
            !WakeScheduling.isOverdueFire(now: now, expected: nil),
            "no armed schedule means nothing to be overdue against"
        )
        expect(
            !WakeScheduling.isOverdueFire(now: now.addingTimeInterval(120), expected: expected),
            "exactly at the slack boundary is still ordinary jitter"
        )
        // Pin the constants themselves: a tenfold typo in either would pass
        // every behavioral case above.
        expect(WakeScheduling.overdueSlack == 120, "overdue slack is two minutes")
        expect(WakeScheduling.graceDelay == 60, "wake grace is one minute")

        // MARK: wake-refresh gating — long sleeps refresh, lid flips don't

        expect(
            WakeScheduling.shouldRefreshAfterWake(lastPoll: nil, now: now, pollInterval: 300),
            "no completed poll yet always warrants the wake refresh"
        )
        expect(
            !WakeScheduling.shouldRefreshAfterWake(
                lastPoll: now.addingTimeInterval(-120), now: now, pollInterval: 300),
            "a 2-minute nap with 5m polling skips the extra refresh"
        )
        expect(
            WakeScheduling.shouldRefreshAfterWake(
                lastPoll: now.addingTimeInterval(-6 * 3600), now: now, pollInterval: 1800),
            "an overnight sleep refreshes even on the 30m preset"
        )
        expect(
            WakeScheduling.shouldRefreshAfterWake(
                lastPoll: now.addingTimeInterval(-300), now: now, pollInterval: 300),
            "exactly one interval of staleness refreshes"
        )

        // MARK: the defect being defended against — the blank "— rate limited" pair

        // Before sleep: healthy readings, the 5h window resets in 90 minutes.
        let beforeSleep = pair(
            reading(0.63, resetIn: 90 * 60), reading(0.41, resetIn: 5 * 86400)
        )
        let wake = now.addingTimeInterval(6 * 3600)
        let rateLimited = pair(
            errored(ClaudeCredentials.rateLimitedMessage),
            errored(ClaudeCredentials.rateLimitedMessage)
        )

        // A 429 straight at wake: the 5h reading died during sleep (reset
        // passed), so its tile blanks to "—" even though we had a number.
        let straight429 = AppUsage.merged(fetched: rateLimited, retaining: beforeSleep, at: wake)
        expect(
            !straight429.fiveHour.hasReading,
            "post-sleep 429 leaves the 5h tile with no reading — its carry expired mid-sleep"
        )
        expect(
            straight429.weekly.hasReading
                && straight429.weekly.error == ClaudeCredentials.rateLimitedMessage,
            "weekly still carries its number with the rate-limited caption"
        )

        // The compounding path: the wake probe 401s first (token rotated out
        // mid-sleep). That is a terminal auth failure — UsageStore assigns
        // the error pair directly, bypassing merged — wiping BOTH windows.
        let tokenExpired = pair(
            errored(ClaudeCredentials.tokenExpiredMessage),
            errored(ClaudeCredentials.tokenExpiredMessage)
        )
        expect(
            ClaudeCredentials.isTerminalAuthFailure(tokenExpired),
            "the expired-token pair is the terminal shape that bypasses carry-forward"
        )
        expect(
            !ClaudeCredentials.isTerminalAuthFailure(rateLimited),
            "a 429 pair is transient — it must keep carrying, never wipe"
        )

        // MARK: refresh-ping gating — only a plain expiry is ping-fixable

        let reauthNeeded = pair(
            errored(ClaudeCredentials.reauthRequiredMessage),
            errored(ClaudeCredentials.reauthRequiredMessage)
        )
        expect(
            ClaudeCredentials.isExpiredTokenFailure(tokenExpired),
            "an expired-token pair is what the CLI refresh ping can fix"
        )
        expect(
            !ClaudeCredentials.isExpiredTokenFailure(reauthNeeded),
            "a missing-scope pair must never ping — refresh re-issues the same scopes"
        )
        expect(
            !ClaudeCredentials.isExpiredTokenFailure(rateLimited),
            "a 429 pair must never ping — it would feed the tripped limiter"
        )

        // The full gate the store consults before spawning — the billing
        // safety invariant. A regression that respawned the ping every poll
        // (silently spending quota) has to fail here.
        expect(
            ClaudeCredentials.shouldSpawnRefreshPing(
                for: tokenExpired, alreadyAttempted: false, reauthInProgress: false),
            "fresh expiry episode with no re-auth running spawns the one ping"
        )
        expect(
            !ClaudeCredentials.shouldSpawnRefreshPing(
                for: tokenExpired, alreadyAttempted: true, reauthInProgress: false),
            "an episode that already pinged never pings again"
        )
        expect(
            !ClaudeCredentials.shouldSpawnRefreshPing(
                for: tokenExpired, alreadyAttempted: false, reauthInProgress: true),
            "the re-auth flow owns the store — no ping under it"
        )
        expect(
            !ClaudeCredentials.shouldSpawnRefreshPing(
                for: rateLimited, alreadyAttempted: false, reauthInProgress: false),
            "only the expired-token shape can ever reach the spawn"
        )

        // After the wipe, the next poll's 429 has nothing to carry: both
        // tiles render "— rate limited" — the screenshot state.
        let afterWipe = AppUsage.merged(
            fetched: rateLimited, retaining: tokenExpired, at: wake.addingTimeInterval(300)
        )
        expect(
            !afterWipe.fiveHour.hasReading && !afterWipe.weekly.hasReading,
            "a 429 after the terminal wipe blanks both tiles"
        )
        expect(
            afterWipe.fiveHour.error == ClaudeCredentials.rateLimitedMessage,
            "the blank tiles caption as rate limited"
        )

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
