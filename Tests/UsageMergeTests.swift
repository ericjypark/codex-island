import Foundation

/// Regression cover for the "0% while rate limited" defect (issue #35).
///
/// `WindowUsage.usedPercent` is a non-optional Double that stays 0 whenever a
/// fetch fails, so "no reading" is bit-identical to "0% used". Anything that
/// renders or alerts on the percentage without gating on `hasReading` first
/// shows a confident 0% — and under the `remaining` toggle a full 100% — for
/// a window nobody has measured.
@main
struct UsageMergeTests {
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

    static func pair(_ five: WindowUsage, _ week: WindowUsage, plan: String? = nil) -> AppUsage {
        AppUsage(fiveHour: five, weekly: week, plan: plan)
    }

    static func main() {
        // MARK: hasReading — the predicate every consumer must gate on

        expect(!errored("rate limited").hasReading, "rate-limited window has no reading")
        expect(!WindowUsage.unknown.hasReading, "the `no data` sentinel has no reading")
        expect(!AppUsage.empty.fiveHour.hasReading, "cold-start .empty has no reading")
        expect(reading(0).hasReading, "a genuine 0% reading is a reading")
        expect(reading(0.42).hasReading, "an ordinary reading is a reading")
        // Carry-forward shape: real value + fresh error. Must still count.
        expect(
            WindowUsage(usedPercent: 0.42, resetAt: nil, error: "rate limited").hasReading,
            "carried-forward value with an attached error is still a reading"
        )

        // MARK: the defect itself — why the gate has to exist

        // Without gating, these two render identically. The second is a real
        // measurement; the first is a struct default from a failed fetch.
        let blind = errored("rate limited").displayedFraction(mode: .used) * 100
        expect(blind == 0, "ungated rate-limited window computes as 0% used")
        let blindRemaining = errored("rate limited").displayedFraction(mode: .remaining) * 100
        expect(blindRemaining == 100, "ungated rate-limited window computes as 100% remaining")

        // MARK: merged — carry the last real reading, attach the new error

        let good = pair(reading(0.16, resetIn: 3600), reading(0.11, resetIn: 5 * 86400), plan: "max")
        let rateLimited = pair(errored("rate limited"), errored("rate limited"))

        let carried = AppUsage.merged(fetched: rateLimited, retaining: good, at: now)
        expect(carried.fiveHour.usedPercent == 0.16, "5h keeps its last real value")
        expect(carried.weekly.usedPercent == 0.11, "weekly keeps its last real value")
        expect(carried.fiveHour.error == "rate limited", "5h surfaces the new error")
        expect(carried.fiveHour.hasReading, "carried window still reads as having data")
        expect(carried.plan == "max", "plan badge survives a failed fetch")

        // A fresh reading always wins, error or not.
        let fresh = pair(reading(0.55, resetIn: 1800), reading(0.44, resetIn: 86400))
        let replaced = AppUsage.merged(fetched: fresh, retaining: good, at: now)
        expect(replaced.fiveHour.usedPercent == 0.55, "fresh reading replaces the retained one")
        expect(replaced.fiveHour.error == nil, "fresh reading clears the error")

        // Nothing to carry: the error passes through as a no-reading window,
        // which is what drives the "—" tile instead of a fabricated 0%.
        let fromCold = AppUsage.merged(fetched: rateLimited, retaining: .empty, at: now)
        expect(!fromCold.fiveHour.hasReading, "cold start with a failed fetch has no reading")
        expect(fromCold.fiveHour.error == "rate limited", "cold start still surfaces the error")

        // Past its own reset, a carried value describes a window that no
        // longer exists — release it rather than show a confident stale number.
        let expiring = pair(reading(0.16, resetIn: 60), reading(0.11, resetIn: 5 * 86400))
        let afterReset = AppUsage.merged(
            fetched: rateLimited, retaining: expiring, at: now.addingTimeInterval(120)
        )
        expect(!afterReset.fiveHour.hasReading, "5h released once its reset time passed")
        expect(afterReset.weekly.usedPercent == 0.11, "weekly still carried — its reset is days out")

        // Windows are independent: one failing must not blank the other.
        let halfFailed = pair(errored("http 500"), reading(0.44, resetIn: 86400))
        let mixed = AppUsage.merged(fetched: halfFailed, retaining: good, at: now)
        expect(mixed.fiveHour.usedPercent == 0.16, "failed 5h carries forward")
        expect(mixed.weekly.usedPercent == 0.44, "successful weekly takes the fresh value")

        // MARK: unreported windows — a parsed omission displaces, a failure carries

        // The sentinel is only the zero-percent "no data" shape. A history
        // seed wears the same caption over a real percentage — still a
        // reading — and fetch failures carry their own messages.
        expect(WindowUsage.unknown.isUnreported, "the parse-omission sentinel is unreported")
        expect(
            !WindowUsage(usedPercent: 0.40, resetAt: nil, error: "no data").isUnreported,
            "a history seed is a reading, not an unreported window"
        )
        expect(!errored("rate limited").isUnreported, "a failed fetch is not an unreported window")

        // Single-window Codex plans (mid-2026): the parsed response reports
        // only weekly; the 5h slot comes back as the sentinel. A prior 5h
        // seed — mislabeled weekly data recorded by pre-fix builds, with no
        // resetAt to ever release it — must be displaced, not carried. This
        // was the frozen "40% · 5h" tile on the upgrade path (#69 review).
        let seeded = pair(
            WindowUsage(usedPercent: 0.40, resetAt: nil, error: "no data"),
            reading(0.11, resetIn: 5 * 86400)
        )
        let weeklyOnly = pair(.unknown, reading(0.40, resetIn: 3 * 86400))
        let displaced = AppUsage.merged(fetched: weeklyOnly, retaining: seeded, at: now)
        expect(!displaced.fiveHour.hasReading, "unreported 5h displaces the stale seed")
        expect(
            displaced.fiveHour.error == WindowUsage.unknown.error,
            "displaced window keeps the passive sentinel caption"
        )
        expect(displaced.weekly.usedPercent == 0.40, "reported weekly takes the fresh value")

        // The displacement must not weaken failure retention: the same
        // seeded value still survives a genuinely failed fetch.
        let seedThroughFailure = AppUsage.merged(
            fetched: pair(errored("http 500"), errored("http 500")), retaining: seeded, at: now
        )
        expect(
            seedThroughFailure.fiveHour.usedPercent == 0.40,
            "a real failure still carries the seeded reading"
        )

        // MARK: window spans bound how long a recorded reading stays usable

        expect(UsageWindow.fiveHour.span == 5 * 3600, "5h span is five hours")
        expect(UsageWindow.weekly.span == 7 * 86400, "weekly span is seven days")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
