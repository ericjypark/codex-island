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

    /// True when BOTH windows carry specifically the expired-token error —
    /// the one terminal failure a spawned CLI ping can fix. A refresh
    /// re-issues the same scope set, so `reauthRequiredMessage` (missing
    /// scope) needs a real `claude /login` instead and must never ping.
    static func isExpiredTokenFailure(_ usage: AppUsage) -> Bool {
        usage.fiveHour.error == tokenExpiredMessage
            && usage.weekly.error == tokenExpiredMessage
    }

    /// Full gating for the refresh ping: the ping-fixable failure shape AND
    /// not already attempted this expiry episode AND no re-auth flow owning
    /// the store. Pure so the test harness can pin the billing-safety
    /// invariant — a regression that respawned the ping every poll would
    /// otherwise pass the suite silently.
    static func shouldSpawnRefreshPing(
        for usage: AppUsage, alreadyAttempted: Bool, reauthInProgress: Bool
    ) -> Bool {
        isExpiredTokenFailure(usage) && !alreadyAttempted && !reauthInProgress
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

        if cachedCreds != nil {
            // Bounded walk over credential candidates. Claude Code rotates
            // the store's token roughly every 8h while our in-memory copy
            // goes stale, so a 401 here usually means "rotated", not
            // "logged out" — surfacing "token expired" without re-reading
            // flashed the re-auth panel (and re-armed the keychain prompt
            // on the follow-up read) once per rotation for a login that was
            // actually fine. A 401/403 excludes that token and re-reads the
            // store, so a fresh credential behind a stale one (rotated
            // keychain item, live file behind a leftover, second account)
            // is reached in the same pass. Only when nothing usable remains
            // does the terminal error surface. The cap bounds doomed probes
            // against pathological many-stale-item keychains.
            var excluded = Set<String>()
            var candidate = cachedCreds
            var keychainScopeFailure = false
            for _ in 0..<3 {
                guard let creds = candidate else { break }
                switch await probe(creds.accessToken, creds.subscriptionType ?? plan) {
                case .success(let u):       return .usage(u)
                // The token is valid — the account is throttled. Re-probing
                // only doubles pressure on a limiter that is sticky once
                // tripped (429 + retry-after: 0 until the account goes quiet).
                case .rateLimited:          return .failed(rateLimitedMessage)
                case .unauthorized:
                    excluded.insert(creds.accessToken)
                    clearCache()
                    lastError = tokenExpiredMessage
                    candidate = readClaudeCreds(excludingTokens: excluded)
                // A refresh re-issues the same scope set, so a 403 on this
                // token can only be fixed by `claude /login` — but a fresh
                // post-login credential may already sit behind this stale
                // one, so keep walking before surfacing re-auth.
                case .scopeInsufficient:
                    excluded.insert(creds.accessToken)
                    clearCache()
                    keychainScopeFailure = true
                    lastError = reauthRequiredMessage
                    candidate = readClaudeCreds(excludingTokens: excluded)
                case .otherError(let e):
                    lastError = e
                    candidate = nil
                }
            }
            if keychainScopeFailure { return .reauthRequired(reauthRequiredMessage) }
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
    /// scope-insufficient probe clears it in `resolveUsage` - the token was
    /// rotated or re-minted externally and the cached copy is stale - and the
    /// credential-store watcher clears it once the fingerprint changes.
    /// Lock-guarded: the poll-timer fetch and the re-auth poll fetch run as
    /// separate tasks off the main actor and can interleave here. Internal
    /// (not private) so ResolveUsageTests can prime it and assert clearing.
    static var cachedClaudeCreds: ClaudeCreds? {
        get { cacheLock.withLock { _cachedClaudeCreds } }
        set { cacheLock.withLock { _cachedClaudeCreds = newValue } }
    }
    private static var _cachedClaudeCreds: ClaudeCreds?
    private static let cacheLock = NSLock()

    /// Injectable keychain sources — production reads the real keychain;
    /// ResolveUsageTests swap in fixtures so the 401 re-read/retry path never
    /// pops the ACL prompt on the machine running the tests.
    static var keychainCandidatesProvider: () -> [KeychainCandidate] = readClaudeKeychainCandidates
    static var keychainModificationDatesProvider: () -> [Date] = claudeKeychainModificationDates

    static func clearCache() {
        cachedClaudeCreds = nil
    }

    /// Reads Claude Code's login from the keychain or file store, or nil if
    /// there isn't a usable one — the caller then falls through to the next
    /// token source. The KEYCHAIN comes first: Claude Code 2.x reads the
    /// keychain as primary and, when a keychain write succeeds, deletes (or
    /// strands) `.credentials.json` — so a coexisting file is the stale
    /// leftover, not the keychain item. Matching the CLI's own read order
    /// keeps us on whichever store it is actually maintaining. (This is the
    /// reverse of the pre-2.x assumption shipped in #56.)
    ///
    /// Keychain shape: Claude Code stores several generic-password items
    /// under the SAME service "Claude Code-credentials": the subscription
    /// tokens live in `claudeAiOauth`, but a separate item written with
    /// acct="unknown" holds only `mcpOAuth` (per-MCP-server tokens). A single
    /// blind lookup can land on the mcpOAuth item and miss the real login —
    /// the bug where the panel showed no Claude usage. Read every item and
    /// let `selectClaudeCreds` pick by content rather than by "first item".
    private static func readClaudeCreds(excludingTokens excluded: Set<String> = []) -> ClaudeCreds? {
        if excluded.isEmpty, let cachedClaudeCreds { return cachedClaudeCreds }
        let creds = selectClaudeCreds(
            from: keychainCandidatesProvider() + readClaudeFileCandidates(),
            excludingTokens: excluded)
        cachedClaudeCreds = creds
        return creds
    }

    // MARK: - File store

    /// Claude Code's file-based credential store, same JSON shape as the
    /// keychain blob. Default on Linux; on macOS the CLI falls back to it
    /// only when the keychain is unavailable (SSH sessions, locked keychain)
    /// — there is no setting to force it. `CLAUDE_CONFIG_DIR` relocates
    /// `~/.claude` — rarely set for a LaunchServices-spawned GUI app, but
    /// honored to match Claude Code's resolution.
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
    /// skipped so a later account still gets its chance. `excludingTokens`
    /// skips candidates holding tokens that already 401/403'd this pass, so
    /// the retry walk can reach a fresh credential sitting BEHIND stale
    /// candidates (stale keychain leftover + live file, or multi-account
    /// keychains) instead of giving up on the first match.
    static func selectClaudeCreds(from candidates: [KeychainCandidate],
                                  excludingTokens excluded: Set<String> = []) -> ClaudeCreds? {
        for candidate in candidates {
            guard let oauth = candidate.blob["claudeAiOauth"] as? [String: Any],
                  let access = oauth["accessToken"] as? String, !access.isEmpty,
                  !excluded.contains(access) else { continue }
            return ClaudeCreds(
                account: candidate.account,
                accessToken: access,
                subscriptionType: oauth["subscriptionType"] as? String
            )
        }
        return nil
    }

    /// Decoded blob for every discovered credential item. Side-effecting:
    /// each secret read spawns `security` (silent), with an in-process
    /// fallback that can prompt — callers go through the `readClaudeCreds`
    /// cache so this runs rarely, not every poll.
    private static func readClaudeKeychainCandidates() -> [KeychainCandidate] {
        claudeKeychainItems().compactMap { item in
            readClaudeKeychainBlob(service: item.service, account: item.account).map {
                KeychainCandidate(account: item.account, blob: $0)
            }
        }
    }

    private static let claudeServiceBase = "Claude Code-credentials"

    /// True for Claude Code's credential item services: the bare name plus
    /// the `-<hash>` variants the CLI derives per custom config dir
    /// (CLAUDE_CONFIG_DIR / CLAUDE_SECURESTORAGE_CONFIG_DIR). Items are
    /// DISCOVERED by enumerating keychain metadata and filtering on this
    /// predicate rather than recomputing the CLI's private sha256 suffix: a
    /// LaunchServices-spawned GUI app rarely inherits the shell's env, and
    /// formula drift would silently miss items — matching what actually
    /// exists works regardless (issue #54 follow-up). Sibling services like
    /// "Claude Code-doctor-probe" do not match. Internal so
    /// ResolveUsageTests can lock the predicate down.
    static func isClaudeCredentialService(_ service: String) -> Bool {
        service == claudeServiceBase || service.hasPrefix(claudeServiceBase + "-")
    }

    /// Attributes-only enumeration of every Claude credential item in the
    /// keychain search list — metadata queries (no `kSecReturnData`) never
    /// trip the ACL prompt. Bare-service items sort first so a
    /// default-config login outranks custom-config-dir variants in
    /// candidate order.
    private static func claudeKeychainItems() -> [(service: String, account: String, modified: Date?)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items
            .compactMap { item -> (service: String, account: String, modified: Date?)? in
                guard let service = item[kSecAttrService as String] as? String,
                      isClaudeCredentialService(service),
                      let account = item[kSecAttrAccount as String] as? String else { return nil }
                return (service, account, item[kSecAttrModificationDate as String] as? Date)
            }
            .sorted { lhs, rhs in
                (lhs.service == claudeServiceBase ? 0 : 1, lhs.service)
                    < (rhs.service == claudeServiceBase ? 0 : 1, rhs.service)
            }
    }

    /// Prompt-free "has the credential store changed?" snapshot: the newest
    /// of the credentials file's mtime and the keychain items' modification
    /// dates, both from metadata-only reads that never trip the ACL prompt.
    /// The re-auth poll loop compares snapshots so it pays the secret read
    /// (and its possible prompt) only once `claude auth login` has actually
    /// written new credentials — not on every 5s tick.
    static func credentialStoreFingerprint() -> Date? {
        var dates = keychainModificationDatesProvider()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: claudeCredentialsFilePath()),
           let modified = attrs[.modificationDate] as? Date {
            dates.append(modified)
        }
        return dates.max()
    }

    /// Metadata-only watch state whose baseline is captured synchronously
    /// before a usage fetch can read the credential cache. Advancing the
    /// baseline before clearing makes one watcher safe to keep across
    /// event-driven refetches and later external account switches.
    final class CredentialStoreWatch {
        private var baseline: Date?

        init() {
            baseline = ClaudeCredentials.credentialStoreFingerprint()
        }

        /// Invalidate a previously read secret only after a prompt-free
        /// metadata snapshot proves Claude Code changed its store. The old
        /// access token can remain valid after an account switch, so HTTP auth
        /// failures alone are not a sufficient invalidation signal (#103).
        func invalidateCachedCredentialsIfStoreChanged() -> Bool {
            let current = ClaudeCredentials.credentialStoreFingerprint()
            guard current != baseline else { return false }
            baseline = current
            ClaudeCredentials.clearCache()
            return true
        }
    }

    private static func claudeKeychainModificationDates() -> [Date] {
        claudeKeychainItems().compactMap { $0.modified }
    }

    /// Decoded JSON blob of one account's item, or nil on any read/parse error.
    ///
    /// Primary path shells out to `/usr/bin/security` — the ONLY reader that
    /// never trips the keychain ACL prompt. Claude Code rewrites this item
    /// with `security add-generic-password -U` on every ~8h token rotation,
    /// and that rewrite RESETS the item's partition list to `apple-tool:`
    /// (verified empirically) — silently wiping any per-app "Always Allow"
    /// grant within hours of the user typing their password for it. No
    /// app-side grant can survive, Developer-ID-signed or not. `security`
    /// itself lives in the `apple-tool:` partition and in the item's ACL
    /// (Claude Code creates the item through it), so its reads stay silent
    /// forever, across every app update. The in-process SecItem read remains
    /// only as a fallback for the day the CLI path breaks — it is the path
    /// that CAN prompt.
    private static func readClaudeKeychainBlob(service: String, account: String) -> [String: Any]? {
        if let blob = readClaudeKeychainBlobViaSecurityCLI(service: service, account: account) {
            return blob
        }
        // Separate breadcrumbs per failure domain: the CLI is the primary
        // path, so its failure must be visible in Console even when the
        // fallback rescues the read.
        NSLog("CodexIsland: security CLI read failed for Claude credentials; trying in-process SecItem read")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            NSLog("CodexIsland: in-process SecItem read also failed for Claude credentials (OSStatus %d)", status)
            return nil
        }
        return decodeClaudeKeychainBlob(data)
    }

    /// Internal (not private) so ResolveUsageTests can cover the hex path.
    static func decodeClaudeKeychainBlob(_ data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        // `security ... -w` hex-dumps the secret when it contains any
        // non-printable byte (Claude Code writes the blob hex-encoded via
        // `-X`, so arbitrary UTF-8 is possible). Decode the dump and
        // re-parse. Plain JSON can never be all hex digits (it starts with
        // '{'), so the orders can't collide.
        guard let hex = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !hex.isEmpty, hex.count % 2 == 0,
              hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }
        return try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    }

    private static func readClaudeKeychainBlobViaSecurityCLI(service: String, account: String) -> [String: Any]? {
        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = [
            "find-generic-password",
            "-s", service,
            "-a", account,
            "-w",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            // Drain stdout BEFORE waitUntilExit — the reverse order
            // deadlocks if the child fills the 64KB pipe buffer.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0,
                  let raw = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let jsonData = raw.data(using: .utf8) else { return nil }
            return decodeClaudeKeychainBlob(jsonData)
        } catch {
            return nil
        }
    }

    /// Account name for an existing Claude Code credential item, from the
    /// attributes-only enumeration — metadata reads never trip the ACL
    /// prompt, so this is safe to call from UI paths (`canPromptReauth`).
    private static func readClaudeKeychainAccount() -> String? {
        claudeKeychainItems().first?.account
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

    /// Detached `claude -p` ping run only for its side effect: the CLI
    /// refreshes an expired access token before answering and writes the
    /// rotated pair back to its credential store, which the credential-store
    /// watch then picks up within seconds. The app itself stays strictly
    /// read-only against the token family — the CLI remains the single
    /// legitimate refresher; this just makes "run claude" happen without the
    /// user. Needed because desktop-app Claude Code injects its own
    /// host-refreshed CLAUDE_CODE_OAUTH_TOKEN and never maintains the CLI
    /// store, so on desktop-only days the keychain token dies ~8h after the
    /// last terminal run and stays dead.
    ///
    /// Cost + safety bounds: haiku model, `--strict-mcp-config` with no
    /// config (zero MCP servers spawned), no tool grants, cwd pinned to
    /// $HOME, stdio detached. Reaches only subscription-OAuth logins by
    /// construction — the expired-token failure only arises from
    /// `claudeAiOauth` candidates, so console/API-key users can never be
    /// billed by it.
    @discardableResult
    static func spawnTokenRefreshPing() -> Bool {
        guard let path = locateClaudeBinary() else { return false }
        let task = Process()
        task.launchPath = path
        task.arguments = ["-p", "ok", "--model", "haiku", "--strict-mcp-config"]
        task.currentDirectoryPath = NSHomeDirectory()
        // Deterministic auth path: the ping exists to refresh the KEYCHAIN
        // login and must never bill anything. Drop the env overrides that
        // would route the CLI to API-key billing or to an injected token
        // that bypasses the keychain writeback (app launched from a shell
        // that exports them).
        var env = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"] {
            env.removeValue(forKey: key)
        }
        task.environment = env
        // Null device, not pipes: a pipe nobody drains wedges a chatty child
        // forever at the 64KB buffer and the Process self-retains — the null
        // device can't block, so no lingering process to leak.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
            return true
        } catch {
            NSLog("CodexIsland: failed to spawn claude token-refresh ping: %@", error.localizedDescription)
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
