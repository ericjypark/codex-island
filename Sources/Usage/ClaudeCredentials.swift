import Foundation

/// Deep module owning Claude OAuth credential acquisition: the
/// env → keychain → refresh → rotation-writeback flow, plus the in-app
/// re-auth helpers. The usage fetcher hands it a probe closure (the single
/// `/api/oauth/usage` HTTP call) and `ClaudeCredentials` drives token
/// selection, deciding when to advance sources and when to surface re-auth.
///
/// The asymmetry between token sources is load-bearing:
///   - An env-token scope-insufficient (403) does NOT short-circuit; we
///     still try the keychain token.
///   - A keychain-token (or refreshed-token) scope-insufficient short-circuits
///     to re-auth, because refresh re-issues the same scope set and cannot
///     recover a missing `user:profile`.
///   - A rate-limited probe short-circuits from ANY source: the limiter is
///     keyed per account, not per token (anthropics/claude-code#30930), so
///     trying another token or refreshing only feeds the limiter.
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

    /// Three token sources, in order of freshness:
    ///   1. CLAUDE_CODE_OAUTH_TOKEN — set by Claude Desktop for child
    ///      processes; always fresh while Desktop is running.
    ///   2. macOS Keychain item "Claude Code-credentials" — stable across
    ///      relaunches; the access token expires after ~8h, after which
    ///      we fall through to refresh.
    ///   3. platform.claude.com/v1/oauth/token refresh — Anthropic
    ///      rotates the refresh_token on every call (the response carries
    ///      a new pair). We must persist that new pair back to the keychain
    ///      via writeClaudeCreds, otherwise Claude Code itself 401s on its
    ///      next refresh because the keychain still holds the now-revoked
    ///      old token. (The OAuth host migrated from console.anthropic.com
    ///      to platform.claude.com — old URL still resolves but is not the
    ///      canonical issuer for fresh tokens.)
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
            // The token is valid — the account is throttled. Refreshing
            // rotates the token family for nothing and the re-probe doubles
            // pressure on a limiter that is sticky once tripped
            // (429 + retry-after: 0 until the account goes quiet).
            case .rateLimited:          return .failed(rateLimitedMessage)
            case .unauthorized:         break
            // Refresh hands back tokens with the same scope set, so it cannot
            // recover from a missing-scope 403. Bail out and surface the only
            // remediation that actually works.
            case .scopeInsufficient:    return .reauthRequired(reauthRequiredMessage)
            case .otherError(let e):    lastError = e
            }

            if let refreshed = await refreshClaudeToken(refreshToken: creds.refreshToken) {
                // Anthropic's OAuth token endpoint rotates the refresh token,
                // so the one we just used is now invalidated server-side. If we
                // do not write the new pair back, Claude Code's next refresh
                // attempt 401s and forces the user to re-run /login. Persist
                // the rotated tokens so the keychain stays in sync with what
                // the server considers valid.
                var updated = creds.oauth
                updated["accessToken"] = refreshed.accessToken
                updated["refreshToken"] = refreshed.refreshToken
                updated["expiresAt"] = refreshed.expiresAt
                writeClaudeCreds(account: creds.account, oauth: updated)

                switch await probe(refreshed.accessToken, plan) {
                case .success(let u):       return .usage(u)
                case .rateLimited:          return .failed(rateLimitedMessage)
                case .unauthorized:         break
                case .scopeInsufficient:    return .reauthRequired(reauthRequiredMessage)
                case .otherError(let e):    lastError = e
                }
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

    private struct ClaudeCreds {
        let account: String
        let accessToken: String
        let refreshToken: String
        let oauth: [String: Any]
        let subscriptionType: String?
    }

    /// Reads the keychain item Claude Code writes on first login. Returns
    /// nil silently on any error — the caller falls through to the next
    /// token source. Captures the account name and the full claudeAiOauth
    /// dict so a refresh can be written back via writeClaudeCreds without
    /// dropping unrelated fields (scopes, subscriptionType, rateLimitTier).
    private static func readClaudeCreds() -> ClaudeCreds? {
        guard let account = readClaudeKeychainAccount() else { return nil }

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
                  let jsonData = raw.data(using: .utf8),
                  let outer = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let oauth = outer["claudeAiOauth"] as? [String: Any],
                  let access = oauth["accessToken"] as? String,
                  let refresh = oauth["refreshToken"] as? String else { return nil }
            let plan = oauth["subscriptionType"] as? String
            return ClaudeCreds(account: account, accessToken: access, refreshToken: refresh, oauth: oauth, subscriptionType: plan)
        } catch {
            return nil
        }
    }

    /// `security add-generic-password -U` requires the original account name
    /// to find and update the existing item. The metadata listing puts it on
    /// a line shaped like: `    "acct"<blob>="ericpark"` — pull the value
    /// from inside the trailing quotes. Returns nil if the line is missing
    /// or the value is `<NULL>`.
    private static func readClaudeKeychainAccount() -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\"acct\"") else { continue }
                guard let eq = trimmed.firstIndex(of: "=") else { return nil }
                let value = trimmed[trimmed.index(after: eq)...]
                guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return nil }
                let inner = value.dropFirst().dropLast()
                return inner.isEmpty ? nil : String(inner)
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Updates the existing `Claude Code-credentials` keychain item in place
    /// (`-U` flag) so the rotated OAuth tokens persist. Best-effort: a
    /// failure here means the next CodexIsland refresh will pay the same
    /// rotation cost again, but Claude Code itself recovers because the
    /// fresh refresh_token we wrote — if the write actually landed — works.
    /// Note: passing the JSON via `-w` makes it briefly visible in `ps` to
    /// processes owned by the same user. The keychain itself is gated by
    /// the same trust boundary, so this is not a meaningful regression.
    @discardableResult
    private static func writeClaudeCreds(account: String, oauth: [String: Any]) -> Bool {
        let payload: [String: Any] = ["claudeAiOauth": oauth]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            NSLog("CodexIsland: failed to serialize rotated Claude tokens for keychain write")
            return false
        }

        let task = Process()
        task.launchPath = "/usr/bin/security"
        task.arguments = [
            "add-generic-password",
            "-U",
            "-s", "Claude Code-credentials",
            "-a", account,
            "-w", json,
        ]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                NSLog("CodexIsland: failed to write rotated Claude tokens to keychain (security exit %d)", task.terminationStatus)
                return false
            }
            return true
        } catch {
            NSLog("CodexIsland: failed to spawn security for keychain write: %@", error.localizedDescription)
            return false
        }
    }

    // MARK: - Refresh

    private struct RefreshedTokens {
        let accessToken: String
        let refreshToken: String
        /// Milliseconds since epoch — matches Claude Code's keychain shape.
        let expiresAt: Int64
    }

    /// Anthropic's token endpoint rotates the refresh_token on every call,
    /// so the response always carries a new pair. Caller is responsible for
    /// persisting them; otherwise the keychain falls out of sync with the
    /// server and any downstream consumer (Claude Code, Claude Desktop)
    /// 401s on its next refresh.
    private static func refreshClaudeToken(refreshToken: String) async -> RefreshedTokens? {
        var req = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = obj["access_token"] as? String,
                  let refresh = obj["refresh_token"] as? String else { return nil }
            // expires_in is seconds; Claude Code stores absolute ms.
            let expiresIn = (obj["expires_in"] as? Double) ?? 28_800
            let expiresAt = Int64((Date().timeIntervalSince1970 + expiresIn) * 1000)
            return RefreshedTokens(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
        } catch {
            return nil
        }
    }

    // MARK: - In-app re-auth

    /// True only when the in-app "Re-authenticate" button can actually do
    /// something useful: the user already has a Claude keychain item
    /// (otherwise they're a Codex-only user — no Claude flow to re-auth) and
    /// the `claude` binary exists at a known install path. We deliberately do
    /// not shell out to `which`; LaunchServices gives the app a stripped PATH
    /// (`/usr/bin:/bin:/usr/sbin:/sbin`), so a `which` call would miss every
    /// Homebrew/nvm/Bun install and the button would silently never appear
    /// for most users.
    static func canPromptReauth() -> Bool {
        guard readClaudeKeychainAccount() != nil else { return false }
        return locateClaudeBinary() != nil
    }

    /// Detached spawn of `claude auth login`. The CLI takes care of opening
    /// the browser, running the localhost OAuth callback listener, and
    /// writing the rotated tokens (with the expanded scope set) back to the
    /// `Claude Code-credentials` keychain item we read on the next refresh.
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
