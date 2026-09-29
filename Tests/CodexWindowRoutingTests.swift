import Foundation

/// Regression cover for the dead Codex "week" tile (2026-07 onward).
///
/// `wham/usage` stopped being positional: plans with a single weekly limit
/// report it as `primary_window` with `limit_window_seconds: 604800` and
/// `secondary_window: null`. The old primary→5h / secondary→weekly mapping
/// rendered the weekly reading in the 5h tile and a permanent "—" in the
/// weekly one. Routing must go by the window's advertised span, with slot
/// order as the fallback for older shapes that omit `limit_window_seconds`.
@main
struct CodexWindowRoutingTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    /// All fixtures go through JSONSerialization — production numbers arrive
    /// as NSNumber, whose `as? Double` bridging native Swift literals don't share.
    static func parse(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    static func rateLimit(fromResponse json: String) -> [String: Any] {
        parse(json)["rate_limit"] as! [String: Any]
    }

    /// The live response observed 2026-08-04 (identifiers redacted): one
    /// window, weekly span, in the primary slot.
    static let weeklyOnlyResponse = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 40,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 332661,
          "reset_at": 1786161248
        },
        "secondary_window": null
      },
      "credits": { "has_credits": false, "unlimited": false }
    }
    """

    /// The original two-window shape older accounts may still get.
    static let twoWindowResponse = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "primary_window": {
          "used_percent": 12,
          "limit_window_seconds": 18000,
          "reset_at": 1786000000
        },
        "secondary_window": {
          "used_percent": 34,
          "limit_window_seconds": 604800,
          "reset_at": 1786161248
        }
      }
    }
    """

    static func main() {
        // The account header selects the same quota bucket as Codex itself.
        // A bearer-only request can return a different percentage with the
        // same reset timestamp.
        let auth = UsageFetcher.parseCodexCredentials(Data("""
        {"tokens":{"access_token":"fixture-token","account_id":"fixture-account"}}
        """.utf8))
        expect(auth != nil, "Codex auth includes an account identity")
        if let auth {
            for path in ["usage", "rate-limit-reset-credits"] {
                let request = UsageFetcher.codexRequest(
                    URL(string: "https://chatgpt.com/backend-api/wham/\(path)")!,
                    credentials: auth
                )
                expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token",
                       "\(path) sends the access token")
                expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fixture-account",
                       "\(path) selects the signed-in account")
            }
        }
        expect(UsageFetcher.parseCodexCredentials(Data("""
        {"tokens":{"access_token":"fixture-token"}}
        """.utf8)) == nil, "missing account ID cannot silently select another quota bucket")

        // MARK: the live 2026-08 shape — weekly lives in the primary slot

        let weeklyOnly = UsageFetcher.routeCodexWindows(rateLimit(fromResponse: weeklyOnlyResponse))
        expect(weeklyOnly.weekly.usedPercent == 0.40, "weekly takes the 604800s primary window")
        expect(
            weeklyOnly.weekly.resetAt == Date(timeIntervalSince1970: 1_786_161_248),
            "weekly keeps the window's reset_at"
        )
        expect(weeklyOnly.weekly.hasReading, "weekly counts as a real reading")
        expect(!weeklyOnly.fiveHour.hasReading, "unreported 5h window has no reading")
        expect(
            weeklyOnly.fiveHour.error == "no data",
            "unreported 5h carries the passive `no data` sentinel, not a fetch error"
        )
        let weeklyOnlyUsage = AppUsage(
            fiveHour: weeklyOnly.fiveHour,
            weekly: weeklyOnly.weekly
        )
        expect(
            weeklyOnlyUsage.peekWindow.hasReading,
            "peek selects the reported weekly window instead of rendering an em dash"
        )
        expect(
            weeklyOnlyUsage.peekWindowIsWeekly,
            "peek chrome knows the weekly window was selected (a11y label, 7d fallback)"
        )

        // MARK: the original two-window shape still routes by span

        let both = UsageFetcher.routeCodexWindows(rateLimit(fromResponse: twoWindowResponse))
        expect(both.fiveHour.usedPercent == 0.12, "18000s primary window lands in 5h")
        expect(both.weekly.usedPercent == 0.34, "604800s secondary window lands in weekly")
        expect(
            AppUsage(fiveHour: both.fiveHour, weekly: both.weekly).peekWindow.usedPercent == 0.12,
            "peek continues to prefer 5h when both windows are reported"
        )
        expect(
            !AppUsage(fiveHour: both.fiveHour, weekly: both.weekly).peekWindowIsWeekly,
            "peek chrome describes the 5h window on two-window plans"
        )

        // MARK: shapes without limit_window_seconds fall back to slot order

        let legacy = UsageFetcher.routeCodexWindows(parse("""
        {
          "primary_window": { "used_percent": 7, "reset_at": 1786000000 },
          "secondary_window": { "used_percent": 21 }
        }
        """))
        expect(legacy.fiveHour.usedPercent == 0.07, "spanless primary defaults to 5h")
        expect(legacy.weekly.usedPercent == 0.21, "spanless secondary defaults to weekly")

        // MARK: a lone 5h-span window leaves weekly unreported, not errored

        let fiveHourOnly = UsageFetcher.routeCodexWindows(parse("""
        {
          "primary_window": { "used_percent": 55, "limit_window_seconds": 18000 },
          "secondary_window": null
        }
        """))
        expect(fiveHourOnly.fiveHour.usedPercent == 0.55, "lone 18000s window lands in 5h")
        expect(!fiveHourOnly.weekly.hasReading, "weekly stays a no-reading window")

        // MARK: same-kind collision — the earlier slot wins, never a silent overwrite

        // Speculative shape (a daily 86400s window classifies as weekly):
        // the primary slot's real weekly reading must survive the sibling.
        let collision = UsageFetcher.routeCodexWindows(parse("""
        {
          "primary_window": { "used_percent": 90, "limit_window_seconds": 604800 },
          "secondary_window": { "used_percent": 10, "limit_window_seconds": 86400 }
        }
        """))
        expect(collision.weekly.usedPercent == 0.90, "primary's weekly reading survives the collision")
        expect(!collision.fiveHour.hasReading, "the colliding sibling doesn't leak into 5h")

        let weeklyDisplay = AppUsage(fiveHour: weeklyOnly.fiveHour, weekly: weeklyOnly.weekly,
            plan: "prolite", reportedWindows: weeklyOnly.reported)
        expect(weeklyDisplay.visibleWindows == [.weekly], "weekly-only plan renders one tile")
        let twoDisplay = AppUsage(fiveHour: both.fiveHour, weekly: both.weekly,
            plan: "pro", reportedWindows: both.reported)
        expect(twoDisplay.visibleWindows == [.fiveHour, .weekly], "API windows override plan-name assumptions")
        let zero = WindowUsage(usedPercent: 0, resetAt: nil, error: nil)
        let zeroWeekly = AppUsage(fiveHour: .unknown, weekly: zero, reportedWindows: [.weekly])
        expect(zeroWeekly.visibleWindows == [.weekly], "genuine zero-percent weekly limit remains visible")
        expect(zeroWeekly.peekWindowIsWeekly && zeroWeekly.peekWindow.hasReading, "zero-percent weekly peek keeps its identity")
        let error = WindowUsage(usedPercent: 0, resetAt: nil, error: "offline")
        let failed = AppUsage(fiveHour: error, weekly: error)
        let merged = AppUsage.merged(fetched: failed, retaining: weeklyDisplay, at: Date())
        expect(merged.visibleWindows == [.weekly], "offline refresh cannot resurrect the absent 5h tile")
        expect(merged.peekWindowIsWeekly, "offline weekly plan keeps weekly peek and alert routing")
        let failedAgain = AppUsage.merged(fetched: failed, retaining: merged, at: Date())
        expect(failedAgain.visibleWindows == [.weekly], "repeated failures retain the discovered windows")
        let changed = AppUsage.merged(fetched: twoDisplay, retaining: merged, at: Date())
        expect(changed.visibleWindows == [.fiveHour, .weekly], "a newly reported 5h limit returns automatically")
        let removed = AppUsage.merged(fetched: weeklyDisplay, retaining: twoDisplay, at: Date())
        expect(removed.visibleWindows == [.weekly], "a removed limit does not remain as a placeholder")
        let fiveOnlyDisplay = AppUsage(fiveHour: zero, weekly: .unknown, reportedWindows: [.fiveHour])
        expect(fiveOnlyDisplay.visibleWindows == [.fiveHour] && !fiveOnlyDisplay.peekWindowIsWeekly,
               "five-hour-only plans keep the correct label")
        expect(AppUsage.empty.visibleWindows.isEmpty, "cold-start unknown does not invent limit windows")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
