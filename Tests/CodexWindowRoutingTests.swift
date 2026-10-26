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

    static func main() async {
        let auth = Data(#"{"tokens":{"access_token":"test-token","account_id":"selected-account"}}"#.utf8)
        for path in ["usage", "rate-limit-reset-credits"] {
            let request = UsageFetcher.codexRequest(path: path, authData: auth)
            expect(request?.url?.absoluteString == "https://chatgpt.com/backend-api/wham/\(path)",
                   "\(path) uses the intended endpoint")
            expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token",
                   "\(path) authenticates with the existing access token")
            expect(request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "selected-account",
                   "\(path) selects the signed-in account instead of the backend default")
        }
        let switchedAuth = Data(#"{"tokens":{"access_token":"new-token","account_id":"other-account"}}"#.utf8)
        let switched = UsageFetcher.codexRequest(path: "usage", authData: switchedAuth)
        expect(switched?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "other-account",
               "changed credentials select the new account")
        expect(switched?.value(forHTTPHeaderField: "Authorization") == "Bearer new-token",
               "token and account come from the same credential snapshot")
        for fixture in [#"{"tokens":{"access_token":"test-token"}}"#,
                        #"{"tokens":{"access_token":"test-token","account_id":" "}}"#] {
            let request = UsageFetcher.codexRequest(path: "usage", authData: Data(fixture.utf8))
            expect(request != nil && request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil,
                   "legacy credentials without an account retain token-only compatibility")
            expect(UsageFetcher.codexAccountID(authData: Data(fixture.utf8)) == nil,
                   "credentials without an account name no account")
        }
        for fixture in ["not-json", "{}", #"{"tokens":{"account_id":"selected-account"}}"#,
                        #"{"tokens":{"access_token":" "}}"#] {
            expect(UsageFetcher.codexRequest(path: "usage", authData: Data(fixture.utf8)) == nil,
                   "unusable credentials cannot create an authenticated request")
        }

        var usageRequests: [URLRequest] = []
        let fetchedUsage = await UsageFetcher.fetchCodex(credentialData: auth) { request in
            usageRequests.append(request)
            guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage"),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else { throw URLError(.badURL) }
            return (Data(weeklyOnlyResponse.utf8), response)
        }
        expect(usageRequests.count == 1, "fetchCodex sends exactly one mocked request")
        expect(usageRequests.first?.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage",
               "fetchCodex sends to the usage endpoint")
        expect(usageRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token",
               "fetchCodex sends the fixture token")
        expect(usageRequests.first?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "selected-account",
               "fetchCodex sends the selected account header")
        expect(fetchedUsage.weekly.usedPercent == 0.40 && fetchedUsage.reportedWindows == [.weekly],
               "fetchCodex parses the mocked weekly quota")
        expect(fetchedUsage.accountID == "selected-account", "fetchCodex tags the usage with the selected account")
        let failedUsage = await UsageFetcher.fetchCodex(credentialData: auth) { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)
            else { throw URLError(.badURL) }
            return (Data(), response)
        }
        expect(failedUsage.accountID == "selected-account" && !failedUsage.weekly.hasReading,
               "a failed fetchCodex still names the attempted account")
        var currentAuth = auth
        let switchedMidFlight = await UsageFetcher.fetchCodex(credentialData: currentAuth) { request in
            currentAuth = switchedAuth
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else { throw URLError(.badURL) }
            return (Data(weeklyOnlyResponse.utf8), response)
        }
        expect(switchedMidFlight.accountID == "other-account" && !switchedMidFlight.weekly.hasReading,
               "a response for an account switched away mid-flight is not applied")
        func midFlight(from initial: Data, to replacement: Data?) async -> AppUsage {
            var current: Data? = initial
            return await UsageFetcher.fetchCodex(credentialData: current) { request in
                current = replacement
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                else { throw URLError(.badURL) }
                return (Data(weeklyOnlyResponse.utf8), response)
            }
        }
        let unreadableMidFlight = await midFlight(from: auth, to: Data("not-json".utf8))
        expect(!unreadableMidFlight.weekly.hasReading && !unreadableMidFlight.accountResolved,
               "a response is not applied when the credential becomes unusable mid-flight")
        let tokenOnlyOld = Data(#"{"tokens":{"access_token":"old-token"}}"#.utf8)
        let tokenOnlyNew = Data(#"{"tokens":{"access_token":"new-token"}}"#.utf8)
        let tokenOnlySwitched = await midFlight(from: tokenOnlyOld, to: tokenOnlyNew)
        expect(!tokenOnlySwitched.weekly.hasReading && tokenOnlySwitched.accountResolved && tokenOnlySwitched.accountID == nil,
               "a token-only credential replaced mid-flight does not apply the old token's response")
        expect((await midFlight(from: tokenOnlyOld, to: tokenOnlyOld)).weekly.hasReading,
               "an unchanged token-only credential still applies its response")
        let rotated = await midFlight(from: auth, to: Data(#"{"tokens":{"access_token":"rotated-token","account_id":"selected-account"}}"#.utf8))
        expect(rotated.weekly.hasReading && rotated.accountID == "selected-account",
               "a same-account token rotation mid-flight still applies the response")
        var thrownAuth = auth
        let switchedThenThrew = await UsageFetcher.fetchCodex(credentialData: thrownAuth) { _ in
            thrownAuth = switchedAuth
            throw URLError(.timedOut)
        }
        expect(switchedThenThrew.accountID == "other-account" && switchedThenThrew.weekly.error == "codex credentials changed",
               "a request that fails after an account switch is tagged with the new account")
        let identity = UsageFetcher.codexLocalIdentity(credentialData: auth)
        expect(identity?.accountID == "selected-account" && identity?.accountResolved == true && identity?.visibleWindows.isEmpty == true,
               "the local credential resolves the account before any request")
        expect(UsageFetcher.codexLocalIdentity(credentialData: Data(#"{"tokens":{"access_token":"t"}}"#.utf8))
                .map { $0.accountResolved && $0.accountID == nil } == true,
               "a local token-only credential resolves to the provider-wide scope")
        expect(UsageFetcher.codexLocalIdentity(credentialData: Data("not-json".utf8)) == nil,
               "an unusable local credential leaves the account unresolved")

        var creditRequests: [URLRequest] = []
        let fetchedCredits = await UsageFetcher.fetchCodexResetCredits(credentialData: auth) { request in
            creditRequests.append(request)
            guard let url = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else { throw URLError(.badURL) }
            let payload = Data(#"{"available_count":2,"credits":[]}"#.utf8)
            return (payload, response)
        }
        expect(creditRequests.count == 1, "fetchCodexResetCredits sends exactly one mocked request")
        expect(creditRequests.first?.url?.absoluteString == "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits",
               "fetchCodexResetCredits sends to the reset-credit endpoint")
        expect(creditRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-token",
               "fetchCodexResetCredits sends the fixture token")
        expect(creditRequests.first?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "selected-account",
               "fetchCodexResetCredits sends the selected account header")
        expect(fetchedCredits?.availableCount == 2, "fetchCodexResetCredits parses the mocked credits")

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
            weeklyOnlyUsage.peekWindow(preferring: .fiveHour).hasReading,
            "peek selects the reported weekly window instead of rendering an em dash"
        )
        expect(
            weeklyOnlyUsage.peekWindowKind(preferring: .fiveHour) == .weekly,
            "peek chrome knows the weekly window was selected (a11y label, 7d fallback)"
        )

        // MARK: the original two-window shape still routes by span

        let both = UsageFetcher.routeCodexWindows(rateLimit(fromResponse: twoWindowResponse))
        expect(both.fiveHour.usedPercent == 0.12, "18000s primary window lands in 5h")
        expect(both.weekly.usedPercent == 0.34, "604800s secondary window lands in weekly")
        expect(
            AppUsage(fiveHour: both.fiveHour, weekly: both.weekly).peekWindow(preferring: .fiveHour).usedPercent == 0.12,
            "peek continues to prefer 5h when both windows are reported"
        )
        expect(
            AppUsage(fiveHour: both.fiveHour, weekly: both.weekly).peekWindowKind(preferring: .fiveHour) == .fiveHour,
            "peek chrome describes the 5h window on two-window plans"
        )

        // MARK: the peek follows the user's preferred window

        let bothUsage = AppUsage(fiveHour: both.fiveHour, weekly: both.weekly, reportedWindows: both.reported)
        expect(
            bothUsage.peekWindowKind(preferring: .weekly) == .weekly
                && bothUsage.peekWindow(preferring: .weekly).usedPercent == 0.34,
            "weekly preference shows the weekly reading on two-window plans"
        )
        let failure = WindowUsage(usedPercent: 0, resetAt: nil, error: "HTTP 500")
        let weeklyFailed = AppUsage(fiveHour: both.fiveHour, weekly: failure, reportedWindows: both.reported)
        expect(
            weeklyFailed.peekWindowKind(preferring: .weekly) == .fiveHour,
            "weekly preference falls back to a real 5h reading when weekly has none"
        )
        let neitherReading = AppUsage(fiveHour: failure, weekly: failure, reportedWindows: both.reported)
        expect(
            neitherReading.peekWindowKind(preferring: .weekly) == .weekly,
            "weekly preference keeps its identity when no window has a reading"
        )
        expect(
            weeklyOnlyUsage.peekWindowKind(preferring: .fiveHour) == .weekly
                && AppUsage(fiveHour: both.fiveHour, weekly: .unknown, reportedWindows: [.fiveHour])
                    .peekWindowKind(preferring: .weekly) == .fiveHour,
            "single-window plans ignore the preference"
        )
        expect(bothUsage.offersPeekWindowChoice, "two-window plans offer the peek window choice")

        // MARK: the selected account travels with the readings

        let accountA = AppUsage(fiveHour: both.fiveHour, weekly: both.weekly, reportedWindows: both.reported, accountID: "acct-a")
        expect(AppUsage.merged(fetched: AppUsage(fiveHour: failure, weekly: failure), retaining: accountA, at: Date()).accountID == "acct-a",
               "a failed fetch keeps the account of the readings it carries")
        expect(AppUsage.merged(fetched: AppUsage(fiveHour: both.fiveHour, weekly: both.weekly, accountID: "acct-b"),
                               retaining: accountA, at: Date()).accountID == "acct-b",
               "a successful fetch for another account takes its identity")
        expect(AppUsage.merged(fetched: AppUsage(fiveHour: both.fiveHour, weekly: both.weekly, reportedWindows: both.reported,
                                                 accountResolved: true),
                               retaining: accountA, at: Date()).accountID == nil,
               "a successful fetch naming no account clears the prior account")
        let failedForA = AppUsage(fiveHour: failure, weekly: failure, accountID: "acct-a")
        let coldFailure = AppUsage.merged(fetched: failedForA, retaining: AppUsage(fiveHour: both.fiveHour, weekly: both.weekly),
                                           at: Date(timeIntervalSince1970: 1_780_000_000))
        expect(coldFailure.accountID == "acct-a" && coldFailure.weekly.hasReading,
               "a failed first poll scopes seeded readings to the attempted account")
        let failedForB = AppUsage(fiveHour: failure, weekly: failure, accountID: "acct-b")
        let switchedFailure = AppUsage.merged(fetched: failedForB, retaining: accountA, at: Date())
        expect(switchedFailure.accountID == "acct-b" && !switchedFailure.weekly.hasReading && !switchedFailure.fiveHour.hasReading,
               "a failed poll for another account does not relabel the prior account's readings")
        expect(switchedFailure.visibleWindows.isEmpty,
               "a failed poll for another account shows no undiscovered windows")
        expect(AppUsage.merged(fetched: failedForB, retaining: switchedFailure, at: Date()).visibleWindows.isEmpty,
               "repeated failures for the new account stay windowless until discovery")
        let failedTokenOnly = AppUsage(fiveHour: failure, weekly: failure, accountResolved: true)
        let tokenOnlySwitch = AppUsage.merged(fetched: failedTokenOnly, retaining: accountA, at: Date())
        expect(tokenOnlySwitch.accountID == nil && tokenOnlySwitch.accountResolved && !tokenOnlySwitch.weekly.hasReading,
               "a failed poll with a token-only credential drops the prior account and its readings")
        expect(AppUsage.merged(fetched: AppUsage(fiveHour: failure, weekly: failure), retaining: tokenOnlySwitch, at: Date()).accountResolved,
               "an unresolved failure keeps the resolved provider-wide scope")

        let zeroSelected = AppUsage(fiveHour: WindowUsage(usedPercent: 0.9, resetAt: nil, error: nil),
                                    weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: nil),
                                    reportedWindows: both.reported)
        let zeroCarried = AppUsage.merged(fetched: AppUsage(fiveHour: failure, weekly: failure), retaining: zeroSelected, at: Date())
        expect(zeroCarried.weekly.hasReading && zeroCarried.peekWindowKind(preferring: .weekly) == .weekly,
               "a carried real zero keeps the selected window across a failed poll")
        expect(AppUsage.merged(fetched: AppUsage(fiveHour: failure, weekly: failure), retaining: zeroCarried, at: Date())
                .peekWindowKind(preferring: .weekly) == .weekly,
               "repeated failures keep carrying the selected zero")
        expect(
            !AppUsage(fiveHour: failure, weekly: failure).offersPeekWindowChoice,
            "a failed fetch before window discovery offers no peek window choice"
        )
        expect(
            !weeklyOnlyUsage.offersPeekWindowChoice
                && !AppUsage(fiveHour: failure, weekly: both.weekly).offersPeekWindowChoice,
            "a plan without both rate windows offers no peek window choice"
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
        expect(zeroWeekly.peekWindowKind(preferring: .fiveHour) == .weekly
            && zeroWeekly.peekWindow(preferring: .fiveHour).hasReading, "zero-percent weekly peek keeps its identity")
        let error = WindowUsage(usedPercent: 0, resetAt: nil, error: "offline")
        let failed = AppUsage(fiveHour: error, weekly: error)
        let merged = AppUsage.merged(fetched: failed, retaining: weeklyDisplay, at: Date())
        expect(merged.visibleWindows == [.weekly], "offline refresh cannot resurrect the absent 5h tile")
        expect(merged.peekWindowKind(preferring: .fiveHour) == .weekly, "offline weekly plan keeps weekly peek and alert routing")
        let failedAgain = AppUsage.merged(fetched: failed, retaining: merged, at: Date())
        expect(failedAgain.visibleWindows == [.weekly], "repeated failures retain the discovered windows")
        let changed = AppUsage.merged(fetched: twoDisplay, retaining: merged, at: Date())
        expect(changed.visibleWindows == [.fiveHour, .weekly], "a newly reported 5h limit returns automatically")
        let removed = AppUsage.merged(fetched: weeklyDisplay, retaining: twoDisplay, at: Date())
        expect(removed.visibleWindows == [.weekly], "a removed limit does not remain as a placeholder")
        let fiveOnlyDisplay = AppUsage(fiveHour: zero, weekly: .unknown, reportedWindows: [.fiveHour])
        expect(fiveOnlyDisplay.visibleWindows == [.fiveHour] && fiveOnlyDisplay.peekWindowKind(preferring: .weekly) == .fiveHour,
               "five-hour-only plans keep the correct label")
        expect(AppUsage.empty.visibleWindows.isEmpty, "cold-start unknown does not invent limit windows")

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
