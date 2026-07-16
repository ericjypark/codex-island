import Foundation
import Security

/// Deep module owning Claude OAuth credential acquisition: the
/// env → keychain flow, plus the in-app re-auth helpers. The usage fetcher
/// hands it a probe closure (the single `/api/oauth/usage` HTTP call) and
/// `ClaudeCredentials` drives token selection, deciding when to advance
/// sources and when to surface re-auth.
///
/// STRICTLY READ-ONLY against the token family: this module never calls the
/// OAuth refresh endpoint and never writes the keychain. Anthropic rotates
/// the refresh_token on every refresh call and revokes the whole token
/// family on old-token reuse — so a second refresher racing Claude Code
/// (or a refresh whose keychain writeback fails) invalidates the user's
/// CLI login. Been there. If the access token is expired we simply report
/// it and wait for Claude Code to refresh and write back.
///
/// The asymmetry between token sources is load-bearing:
///   - An env-token scope-insufficient (403) does NOT short-circuit; we
///     still try the keychain token.
///   - A keychain-token scope-insufficient short-circuits to re-auth,
///     because a refresh re-issues the same scope set — only a fresh
///     `claude /login` can recover a missing `user:profile`.
///   - A rate-limited probe short-circuits from ANY source: the limiter is
///     keyed per account, not per token (anthropics/claude-code#30930), so
///     trying another token only feeds the limiter.
enum ClaudeCredentials {
    /// Emitted as `WindowUsage.error` when the keychain token is structurally
    /// valid but missing a scope the Claude usage endpoint now requires
    /// (`user:profile`, added mid-2026). The UI layer matches on this exact
    /// string to swap the error caption for an in-app re-auth button.
    static let reauthRequiredMessage = "re-login: claude /login"

    /// Emitted as `WindowUsage.error` when the usage endpoint rate-limits us
    /// (HTTP 429, or 200 with a rate_limit_error body). `UsageStore` matches
    /// on this exact string to arm the post-429 fetch cooldown.
    static let rateLimitedMessage = "rate limited"

    /// Emitted as `WindowUsage.error` when the keychain access token has
    /// expired. We never refresh it ourselves (see the type doc); Claude Code
    /// refreshes and writes back the next time the user runs it.
    static let tokenExpiredMessage = "token expired — run claude"

    /// True when a probe error is one the in-app re-auth flow can act on: a
    /// terminal auth failure — an expired keychain token (401) or a token
    /// missing a scope the usage endpoint now requires (403). Distinct from a
    /// transient 429/network error, which self-heals and must NOT trigger the
    /// re-auth prompt. Views key the "Re-authenticate" button and its caption
    /// on this; `UsageStore` uses `isTerminalAuthFailure` to let these replace
    /// a stale good value instead of retaining it.
    static func isReauthActionable(_ error: String?) -> Bool {
        error == tokenExpiredMessage || error == reauthRequiredMessage
    }

    /// True when BOTH windows carry a reauth-actionable error — the token
    /// itself is unusable, not one window transiently failing. `UsageStore`'s
    /// "don't clobber good values" retention makes an exception for this so the
    /// panel surfaces the re-auth prompt instead of freezing on numbers it can
    /// no longer refresh.
    static func isTerminalAuthFailure(_ usage: AppUsage) -> Bool {
        isReauthActionable(usage.fiveHour.error) && isReauthActionable(usage.weekly.error)
    }

    /// Outcome of a single usage-endpoint probe against one token. The fetcher
    /// owns the HTTP + parsing and reports back through this; `ClaudeCredentials`
    /// interprets it to decide whether to advance to the next token source.
    enum ProbeOutcome {
        case success(AppUsage)
        case rateLimited
        case unauthorized
        /// Token is structurally valid but missing a scope the server now requires
        /// (Anthropic added `user:profile` to /api/oauth/usage in mid-2026).
        /// Refresh won't help — only a fresh `claude /login` re-issues with the
        /// expanded scope set.
        case scopeInsufficient
        case otherError(String)
    }

    /// Resolution of the full token flow once probed against the usage endpoint.
    enum Resolution {
        /// A token was accepted by the probe; carries the parsed usage.
        case usage(AppUsage)
        /// A fresh `claude /login` is required (scope-insufficient on a keychain
        /// or refreshed token). Carries the exact UI-facing error message.
        case reauthRequired(String)
        /// No token source produced usage; carries the last error seen, which
        /// the fetcher renders as the error caption.
        case failed(String)
    }

    // MARK: - Resolution

    /// Two token sources, in order of freshness:
    ///   1. CLAUDE_CODE_OAUTH_TOKEN — set by Claude Desktop for child
    ///      processes; always fresh while Desktop is running.
    ///   2. macOS Keychain item "Claude Code-credentials" — stable across
    ///      relaunches; the access token expires after ~8h. When it has,
    ///      we surface "token expired" and wait for Claude Code to refresh
    ///      it — deliberately NOT refreshing ourselves (see the type doc).
    static func resolveUsage(probe: (_ token: String, _ plan: String?) async -> ProbeOutcome) async -> Resolution {
        let defaultError = "auth required — run claude"
        var lastError = defaultError
        // Plan tier ships in the keychain dict only — Anthropic's usage
        // endpoint doesn't echo it back. We peek the keychain even on the
        // env-token path so the chip works for users whose token came from
        // Claude Desktop's child env rather than from `claude /login`.
        let cachedCreds = readClaudeCreds()
        let plan = cachedCreds?.subscriptionType

        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            switch await probe(envToken, plan) {
            case .success(let u):       return .usage(u)
            // Account-level limit: the keychain token shares the bucket, so a
            // second probe is just another hit on a tripped limiter.
            case .rateLimited:          return .failed(rateLimitedMessage)
            case .unauthorized:         break
            case .scopeInsufficient:    lastError = reauthRequiredMessage
            case .otherError(let e):    lastError = e
            }
        }

        if let creds = cachedCreds {
            switch await probe(creds.accessToken, plan) {
            case .success(let u):       return .usage(u)
            // The token is valid — the account is throttled. Re-probing only
            // doubles pressure on a limiter that is sticky once tripped
            // (429 + retry-after: 0 until the account goes quiet).
            case .rateLimited:          return .failed(rateLimitedMessage)
            // Expired access token. Claude Code will refresh it on its next
            // run; we stay read-only and show the stale state until then.
            // Drop the cached creds so the next poll re-reads the keychain —
            // otherwise a token Claude Code already rotated stays stale in
            // the cache forever and the chip never recovers.
            case .unauthorized:
                clearCache()
                lastError = tokenExpiredMessage
            // A refresh re-issues the same scope set, so it cannot recover
            // from a missing-scope 403. Surface the only remediation that
            // actually works. Clear the cache so the re-minted token from
            // `claude /login` is picked up on the next poll.
            case .scopeInsufficient:
                clearCache()
                return .reauthRequired(reauthRequiredMessage)
            case .otherError(let e):    lastError = e
            }
        }

        // No usage, and no probe set a more specific error: if we never had a
        // login because the keychain returned a stray item (its account isn't
        // the current user), say so rather than the generic "auth required".
        if lastError == defaultError, cachedCreds == nil,
           let account = readClaudeKeychainAccount(), account != NSUserName() {
            lastError = "multiple keychain logins"
        }

        return .failed(lastError)
    }

    // MARK: - Keychain

    /// Internal (not private) so ResolveUsageTests can assert which item the
    /// multi-account selection picks.
    struct ClaudeCreds {
        let account: String
        let accessToken: String
        let subscriptionType: String?
    }

    /// One decoded keychain item under the Claude service.
    struct KeychainCandidate {
        let account: String
        let blob: [String: Any]
    }

    /// Last successful keychain read, held so ordinary polls don't re-trigger
    /// the keychain ACL prompt every cycle. Only a successful read is cached
    /// (nil results retry on the next poll). Invalidation: an unauthorized or
    /// scope-insufficient probe clears it in `resolveUsage` — the token was
    /// rotated or re-minted externally and the cached copy is stale — and the
    /// in-app re-auth poll loop clears it before each fetch. Internal (not
    /// private) so ResolveUsageTests can prime it and assert the clearing.
    static var cachedClaudeCreds: ClaudeCreds?

    static func clearCache() {
        cachedClaudeCreds = nil
    }

    /// Reads Claude Code's login from the file store or keychain, or nil if
    /// there isn't a usable one — the caller then falls through to the next
    /// token source. The file store (`~/.claude/.credentials.json`) comes
    /// FIRST: when the file exists, Claude Code itself reads and maintains it
    /// in preference to the keychain, so a coexisting keychain item is a
    /// stale leftover (issue #54 — users delete the keychain item to escape
    /// its ACL prompts, and the file never prompts at all).
    ///
    /// Keychain shape: Claude Code stores several generic-password items
    /// under the SAME service "Claude Code-credentials": the subscription
    /// tokens live in `claudeAiOauth`, but a separate item written with
    /// acct="unknown" holds only `mcpOAuth` (per-MCP-server tokens). A single
    /// blind lookup can land on the mcpOAuth item and miss the real login —
    /// the bug where the panel showed no Claude usage. Read every item and
    /// let `selectClaudeCreds` pick by content rather than by "first item".
    private static func readClaudeCreds() -> ClaudeCreds? {
        if let cachedClaudeCreds { return cachedClaudeCreds }
        let creds = selectClaudeCreds(
            from: readClaudeFileCandidates() + readClaudeKeychainCandidates())
        cachedClaudeCreds = creds
        return creds
    }

    // MARK: - File store

    /// Claude Code's file-based credential store, same JSON shape as the
    /// keychain blob. Default on Linux; on macOS users opt in (and typically
    /// delete the keychain item). `CLAUDE_CONFIG_DIR` relocates `~/.claude`
    /// — rarely set for a LaunchServices-spawned GUI app, but honored to
    /// match Claude Code's resolution.
    private static func claudeCredentialsFilePath() -> String {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? "\(NSHomeDirectory())/.claude"
        return "\(configDir)/.credentials.json"
    }

    /// Internal (not private) so ResolveUsageTests can point it at a fixture
    /// via CLAUDE_CONFIG_DIR and assert the decoded candidate.
    static func readClaudeFileCandidates() -> [KeychainCandidate] {
        guard let data = FileManager.default.contents(atPath: claudeCredentialsFilePath()),
              let blob = decodeClaudeKeychainBlob(data) else { return [] }
        return [KeychainCandidate(account: NSUserName(), blob: blob)]
    }

    /// First candidate carrying a usable `claudeAiOauth` (non-empty access
    /// token). Pure — exposed for ResolveUsageTests, which locks down the
    /// multi-item selection. An empty-token item is a logged-out remnant,
    /// skipped so a later account still gets its chance.
    static func selectClaudeCreds(from candidates: [KeychainCandidate]) -> ClaudeCreds? {
        for candidate in candidates {
            guard let oauth = candidate.blob["claudeAiOauth"] as? [String: Any],
                  let access = oauth["accessToken"] as? String, !access.isEmpty else { continue }
            return ClaudeCreds(
                account: candidate.account,
                accessToken: access,
                subscriptionType: oauth["subscriptionType"] as? String
            )
        }
        return nil
    }

    /// Decoded blob for every account under the service. Side-effecting: the
    /// secret read trips the keychain ACL prompt (in-process first, `security`
    /// CLI fallback) — callers go through the `readClaudeCreds` cache so this
    /// runs rarely, not every poll.
    private static func readClaudeKeychainCandidates() -> [KeychainCandidate] {
        let accounts = claudeKeychainAccounts()
        return accounts.compactMap { account in
            readClaudeKeychainBlob(account: account).map {
                KeychainCandidate(account: account, blob: $0)
            }
        }
    }

    /// Every account name under the "Claude Code-credentials" service. An
    /// attributes-only SecItem query (no `kSecReturnData`) does not trip the
    /// keychain ACL prompt — only reading the secret value would.
    private static func claudeKeychainAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// Decoded JSON blob of one account's item, or nil on any read/parse error.
    ///
    /// Primary path is an in-process `SecItemCopyMatching`, so the keychain
    /// ACL prompt is attributed to CodexIsland (and "Always Allow" grants
    /// this app) instead of the generic `/usr/bin/security` binary. The CLI
    /// fallback stays default-ON: the app is ad-hoc signed, so its keychain
    /// identity changes with every build and a previously granted in-process
    /// ACL entry can stop matching after an update. `security` is
    /// Apple-signed with a stable identity, so a grant to it persists — a
    /// denied/failed SecItem read must degrade to the old working path, not
    /// to silently-missing Claude usage.
    private static func readClaudeKeychainBlob(account: String) -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            NSLog("CodexIsland: SecItemCopyMatching for Claude credentials failed (OSStatus %d), falling back to security CLI", status)
            return readClaudeKeychainBlobViaSecurityCLI(account: account)
        }
        return decodeClaudeKeychainBlob(data)
    }

    private static func decodeClaudeKeychainBlob(_ data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func readClaudeKeychainBlobViaSecurityCLI(account: String) -> [String: Any]? {
        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = [
            "find-generic-password",
            "-s", "Claude Code-credentials",
            "-a", account,
            "-w",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = raw.data(using: .utf8) else { return nil }
            return decodeClaudeKeychainBlob(jsonData)
        } catch {
            return nil
        }
    }

    /// Account name for an existing Claude Code credential item, from the
    /// attributes-only SecItem query — metadata reads never trip the ACL
    /// prompt, so this is safe to call from UI paths (`canPromptReauth`).
    private static func readClaudeKeychainAccount() -> String? {
        claudeKeychainAccounts().first
    }

    // MARK: - In-app re-auth

    /// True only when the in-app "Re-authenticate" button can actually do
    /// something useful: the user already has a Claude login store (keychain
    /// item or credentials file — otherwise they're a Codex-only user, no
    /// Claude flow to re-auth) and the `claude` binary exists at a known
    /// install path. We deliberately do not shell out to `which`;
    /// LaunchServices gives the app a stripped PATH
    /// (`/usr/bin:/bin:/usr/sbin:/sbin`), so a `which` call would miss every
    /// Homebrew/nvm/Bun install and the button would silently never appear
    /// for most users.
    static func canPromptReauth() -> Bool {
        guard readClaudeKeychainAccount() != nil
                || FileManager.default.fileExists(atPath: claudeCredentialsFilePath()) else { return false }
        return locateClaudeBinary() != nil
    }

    /// Detached spawn of `claude auth login`. The CLI takes care of opening
    /// the browser, running the localhost OAuth callback listener, and
    /// writing the rotated tokens (with the expanded scope set) back to the
    /// `Claude Code-credentials` keychain item we read on the next poll.
    /// Returns false only if `claude` couldn't be located — the spawn itself
    /// is fire-and-forget; the caller polls for the keychain update.
    @discardableResult
    static func spawnReauth() -> Bool {
        guard let path = locateClaudeBinary() else { return false }
        let task = Process()
        task.launchPath = path
        task.arguments = ["auth", "login"]
        // Detach stdio: we don't want the CLI's progress output to leak into
        // our app's stderr, and we explicitly do not want it inheriting our
        // controlling terminal (we don't have one — we're a GUI app).
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        task.standardInput = Pipe()
        do {
            try task.run()
            return true
        } catch {
            NSLog("CodexIsland: failed to spawn claude auth login: %@", error.localizedDescription)
            return false
        }
    }

    /// Common install locations for the Claude Code CLI, in priority order.
    /// nvm is special-cased because its bin path embeds a node version we
    /// can't predict. We don't probe Volta/asdf/etc.; users with exotic
    /// installs will fall through to the manual `claude /login` path.
    private static func locateClaudeBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            // Sort descending so the newest installed Node version wins —
            // matches what `nvm use` would resolve to in practice.
            for version in versions.sorted(by: >) {
                let candidate = "\(nvmRoot)/\(version)/bin/claude"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
}
