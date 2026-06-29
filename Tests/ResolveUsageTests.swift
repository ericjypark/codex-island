import Foundation

/// Regression tests for ClaudeCredentials.resolveUsage, run by
/// scripts/run-tests.sh (no XCTest — the app builds with bare swiftc, so the
/// harness does too). The runner sets CLAUDE_CODE_OAUTH_TOKEN to a stub value
/// so the env-token path drives the injected probe deterministically on any
/// machine, with or without a real "Claude Code-credentials" keychain item.
///
/// Why the rate-limited case is locked down (issue #35): Anthropic's
/// /api/oauth/usage limiter is account-keyed and sticky once tripped
/// (anthropics/claude-code#30930). resolveUsage must short-circuit on the
/// first rate-limited probe — if a regression reintroduces the old
/// fall-through, every poll cycle re-probes and rotates the refresh-token
/// family against a throttled account. (On a dev machine with real keychain
/// creds, such a regression would also make THIS test perform one live token
/// rotation before the probe-count assertion catches it — noisy but
/// recoverable, since the rotation writeback path is exercised by the app
/// daily.)
@main
struct ResolveUsageTests {
    final class ProbeCounter {
        var calls = 0
    }

    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            print("PASS \(label)")
        } else {
            print("FAIL \(label)")
            failures += 1
        }
    }

    static func main() async {
        guard ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"] == "test-stub-token" else {
            print("FAIL harness must run via scripts/run-tests.sh (env token stub missing)")
            exit(1)
        }

        // T1 — a rate-limited probe short-circuits the whole resolution:
        // exactly one probe (no fallback to the next token source, no
        // refresh + re-probe) and the exact error string the UI and
        // UsageStore cooldown match on.
        let t1 = ProbeCounter()
        let r1 = await ClaudeCredentials.resolveUsage { _, _ in
            t1.calls += 1
            return .rateLimited
        }
        if case .failed(let msg) = r1 {
            expect(msg == ClaudeCredentials.rateLimitedMessage, "T1 resolution is .failed(rateLimitedMessage)")
        } else {
            expect(false, "T1 resolution is .failed(rateLimitedMessage)")
        }
        expect(t1.calls == 1, "T1 probes exactly once (got \(t1.calls))")

        // T2 — a successful probe passes usage through untouched.
        let t2 = ProbeCounter()
        let fetched = AppUsage(
            fiveHour: WindowUsage(usedPercent: 0.13, resetAt: nil, error: nil),
            weekly: WindowUsage(usedPercent: 0.14, resetAt: nil, error: nil)
        )
        let r2 = await ClaudeCredentials.resolveUsage { _, _ in
            t2.calls += 1
            return .success(fetched)
        }
        if case .usage(let u) = r2 {
            expect(u.fiveHour.usedPercent == 0.13 && u.weekly.usedPercent == 0.14, "T2 usage passes through")
        } else {
            expect(false, "T2 usage passes through")
        }
        expect(t2.calls == 1, "T2 probes exactly once (got \(t2.calls))")

        // T3 — multi-item keychain selection. Claude Code writes several items
        // under one service name; a stray acct="unknown" item holds only
        // mcpOAuth. Selection must skip it (and any logged-out empty-token
        // item) and pick the item that actually carries claudeAiOauth.
        let candidates = [
            ClaudeCredentials.KeychainCandidate(account: "unknown", blob: ["mcpOAuth": ["server": "x"]]),
            ClaudeCredentials.KeychainCandidate(account: "loggedout", blob: ["claudeAiOauth": ["accessToken": "", "refreshToken": ""]]),
            ClaudeCredentials.KeychainCandidate(account: "ericpark", blob: [
                "mcpOAuth": ["server": "x"],
                "claudeAiOauth": ["accessToken": "at", "refreshToken": "rt", "subscriptionType": "max"],
            ]),
        ]
        let picked = ClaudeCredentials.selectClaudeCreds(from: candidates)
        expect(picked?.account == "ericpark", "T3 selects the claudeAiOauth item, not the mcpOAuth/empty ones")
        expect(picked?.subscriptionType == "max", "T3 carries subscriptionType from the picked item")
        expect(picked?.outer["mcpOAuth"] != nil, "T3 keeps sibling top-level keys in outer")
        expect(ClaudeCredentials.selectClaudeCreds(from: [
            ClaudeCredentials.KeychainCandidate(account: "unknown", blob: ["mcpOAuth": [:]]),
        ]) == nil, "T3 returns nil when no item carries claudeAiOauth")

        // T4 — rotation writeback preserves every sibling key. Writing only
        // {"claudeAiOauth": …} back to an item that also held mcpOAuth would
        // clobber Claude Code's MCP auth.
        let rotated = ClaudeCredentials.rotatedPayload(
            outer: ["mcpOAuth": ["server": "x"], "claudeAiOauth": ["accessToken": "old"]],
            oauth: ["accessToken": "new", "refreshToken": "rt2"]
        )
        expect(rotated["mcpOAuth"] != nil, "T4 rotation payload keeps mcpOAuth")
        expect((rotated["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String == "new", "T4 rotation payload updates claudeAiOauth")

        // The store and views match these exact strings; a reword is a
        // breaking change for them, not a copy edit.
        expect(ClaudeCredentials.rateLimitedMessage == "rate limited", "rateLimitedMessage literal is stable")
        expect(ClaudeCredentials.reauthRequiredMessage == "re-login: claude /login", "reauthRequiredMessage literal is stable")

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("all tests passed")
    }
}
