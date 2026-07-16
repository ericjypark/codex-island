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
/// fall-through, every poll cycle re-probes against a throttled account.
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

        // Prime the creds cache so resolveUsage never reads the developer's
        // real keychain — an actual read would pop the keychain ACL prompt on
        // every test run and make results depend on the machine's login state.
        ClaudeCredentials.cachedClaudeCreds = ClaudeCredentials.ClaudeCreds(
            account: "test-stub", accessToken: "stub-keychain-token", subscriptionType: nil)

        // T1 — a rate-limited probe short-circuits the whole resolution:
        // exactly one probe (no fallback to the next token source) and the
        // exact error string the UI and UsageStore cooldown match on.
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
        expect(ClaudeCredentials.selectClaudeCreds(from: [
            ClaudeCredentials.KeychainCandidate(account: "unknown", blob: ["mcpOAuth": [:]]),
        ]) == nil, "T3 returns nil when no item carries claudeAiOauth")

        // T4 — an unauthorized keychain-token probe must clear the creds
        // cache, or a token Claude Code rotated externally stays stale in
        // the cache forever and the chip never recovers past "token expired".
        // Priming the cache short-circuits the real keychain read, keeping
        // this deterministic on any machine.
        ClaudeCredentials.cachedClaudeCreds = ClaudeCredentials.ClaudeCreds(
            account: "primed", accessToken: "stale-token", subscriptionType: "max")
        let t4 = ProbeCounter()
        let r4 = await ClaudeCredentials.resolveUsage { _, _ in
            t4.calls += 1
            return .unauthorized
        }
        // Env stub token probes first (unauthorized → falls through), then
        // the primed keychain creds probe (unauthorized → clears cache).
        expect(t4.calls == 2, "T4 probes env then cached keychain token (got \(t4.calls))")
        expect(ClaudeCredentials.cachedClaudeCreds == nil, "T4 unauthorized keychain probe clears the creds cache")
        if case .failed(let msg) = r4 {
            expect(msg == ClaudeCredentials.tokenExpiredMessage, "T4 resolution is .failed(tokenExpiredMessage)")
        } else {
            expect(false, "T4 resolution is .failed(tokenExpiredMessage)")
        }
        ClaudeCredentials.clearCache()

        // T5 — file credential store (issue #54). Users who migrated to
        // ~/.claude/.credentials.json and deleted the keychain item must
        // still get usage. Point CLAUDE_CONFIG_DIR at a fixture and assert
        // the decoded candidate feeds the same selection as keychain items.
        let fixtureDir = NSTemporaryDirectory() + "codexisland-tests-\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: fixtureDir, withIntermediateDirectories: true)
        let fixture = """
        {"claudeAiOauth": {"accessToken": "file-at", "refreshToken": "file-rt", "subscriptionType": "pro"}}
        """
        FileManager.default.createFile(atPath: fixtureDir + "/.credentials.json", contents: Data(fixture.utf8))
        setenv("CLAUDE_CONFIG_DIR", fixtureDir, 1)
        let fileCandidates = ClaudeCredentials.readClaudeFileCandidates()
        let filePicked = ClaudeCredentials.selectClaudeCreds(from: fileCandidates)
        expect(filePicked?.accessToken == "file-at", "T5 file store candidate decodes and is selectable")
        expect(filePicked?.subscriptionType == "pro", "T5 file store carries subscriptionType")
        // File store outranks a coexisting (stale) keychain item — Claude
        // Code itself prefers the file when it exists.
        let mixed = ClaudeCredentials.selectClaudeCreds(from: fileCandidates + [
            ClaudeCredentials.KeychainCandidate(account: "ericpark", blob: [
                "claudeAiOauth": ["accessToken": "stale-keychain-at"],
            ]),
        ])
        expect(mixed?.accessToken == "file-at", "T5 file store wins over a coexisting keychain item")
        // Keep CLAUDE_CONFIG_DIR pinned to the (now deleted) fixture dir so
        // this assertion never touches a real ~/.claude on the dev machine.
        try? FileManager.default.removeItem(atPath: fixtureDir)
        expect(ClaudeCredentials.readClaudeFileCandidates().isEmpty, "T5 missing file yields no candidates")
        unsetenv("CLAUDE_CONFIG_DIR")

        // T6 — auth-failure classification. UsageStore lets a terminal auth
        // error (expired token / missing scope) REPLACE a stale good value,
        // while a transient 429/network error is retained. Both predicates
        // must key only on the two actionable sentinels, and
        // isTerminalAuthFailure must require BOTH windows to carry one — a
        // single-window failure is a transient per-window glitch, not a dead
        // token.
        expect(ClaudeCredentials.isReauthActionable(ClaudeCredentials.tokenExpiredMessage),
               "T6 expired token is reauth-actionable")
        expect(ClaudeCredentials.isReauthActionable(ClaudeCredentials.reauthRequiredMessage),
               "T6 scope-insufficient is reauth-actionable")
        expect(!ClaudeCredentials.isReauthActionable(ClaudeCredentials.rateLimitedMessage),
               "T6 rate-limited is NOT reauth-actionable")
        expect(!ClaudeCredentials.isReauthActionable("no data"), "T6 no-data is NOT reauth-actionable")
        expect(!ClaudeCredentials.isReauthActionable(nil), "T6 nil error is NOT reauth-actionable")

        func pair(_ msg: String?) -> AppUsage {
            AppUsage(
                fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: msg),
                weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: msg))
        }
        expect(ClaudeCredentials.isTerminalAuthFailure(pair(ClaudeCredentials.tokenExpiredMessage)),
               "T6 both-window expired is a terminal auth failure")
        expect(ClaudeCredentials.isTerminalAuthFailure(pair(ClaudeCredentials.reauthRequiredMessage)),
               "T6 both-window scope is a terminal auth failure")
        expect(!ClaudeCredentials.isTerminalAuthFailure(pair(ClaudeCredentials.rateLimitedMessage)),
               "T6 rate-limited is NOT a terminal auth failure")
        expect(!ClaudeCredentials.isTerminalAuthFailure(pair(nil)),
               "T6 good usage is NOT a terminal auth failure")
        expect(!ClaudeCredentials.isTerminalAuthFailure(AppUsage(
            fiveHour: WindowUsage(usedPercent: 0.1, resetAt: nil, error: nil),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: ClaudeCredentials.tokenExpiredMessage))),
            "T6 single-window failure is NOT terminal (needs both)")

        // The store and views match these exact strings; a reword is a
        // breaking change for them, not a copy edit.
        expect(ClaudeCredentials.rateLimitedMessage == "rate limited", "rateLimitedMessage literal is stable")
        expect(ClaudeCredentials.reauthRequiredMessage == "re-login: claude /login", "reauthRequiredMessage literal is stable")
        expect(ClaudeCredentials.tokenExpiredMessage == "token expired — run claude", "tokenExpiredMessage literal is stable")

        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("all tests passed")
    }
}
