import Foundation

enum UsageFetcher {
    // MARK: - Sentinels

    /// Emitted as `WindowUsage.error` when the keychain token is structurally
    /// valid but missing a scope the Claude usage endpoint now requires
    /// (`user:profile`, added mid-2026). The UI layer matches on this exact
    /// string to swap the error caption for an in-app re-auth button.
    static let claudeReauthRequiredMessage = "re-login: claude /login"

    // MARK: - Codex

    /// Codex usage lives at chatgpt.com/backend-api/wham/usage and accepts
    /// the access_token from ~/.codex/auth.json. The endpoint is reliable
    /// and rarely rate-limited, so this is the easy half of the integration.
    static func fetchCodex() async -> AppUsage {
        guard let token = readCodexAccessToken() else {
            return errorPair("no codex auth")
        }

        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // 401 means the access_token in ~/.codex/auth.json has expired.
            // The Codex CLI rotates this token on its own — there's nothing
            // we can do from here, so surface the exact remediation step.
            if status == 401 {
                return errorPair("auth expired — codex login")
            }
            if status != 200 {
                return errorPair("http \(status)")
            }

            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rl = obj["rate_limit"] as? [String: Any] else {
                return errorPair("parse error")
            }
            return AppUsage(
                fiveHour: parseCodexWindow(rl["primary_window"]),
                weekly: parseCodexWindow(rl["secondary_window"]),
                plan: obj["plan_type"] as? String
            )
        } catch {
            return errorPair(error.localizedDescription)
        }
    }

    private static func errorPair(_ message: String) -> AppUsage {
        AppUsage(
            fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: message)
        )
    }

    private static func readCodexAccessToken() -> String? {
        let path = NSString("~/.codex/auth.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String else { return nil }
        return token
    }

    private static func parseCodexWindow(_ obj: Any?) -> WindowUsage {
        guard let d = obj as? [String: Any] else { return .unknown }
        let used = (d["used_percent"] as? Double) ?? 0
        let resetAt = (d["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return WindowUsage(usedPercent: used / 100, resetAt: resetAt, error: nil)
    }

    // MARK: - Claude

    /// Anthropic doesn't ship a usage endpoint for end users — Claude Code
    /// itself talks to api.anthropic.com/api/oauth/usage with a beta header
    /// and a User-Agent that identifies as the CLI. We replicate that.
    ///
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
    static func fetchClaude() async -> AppUsage {
        var lastError = "auth required — run claude"
        // Plan tier ships in the keychain dict only — Anthropic's usage
        // endpoint doesn't echo it back. We peek the keychain even on the
        // env-token path so the chip works for users whose token came from
        // Claude Desktop's child env rather than from `claude /login`.
        let cachedCreds = readClaudeCreds()
        let plan = cachedCreds?.subscriptionType

        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            switch await fetchClaudeUsage(token: envToken, plan: plan) {
            case .success(let u):       return u
            case .rateLimited:          lastError = "rate limited"
            case .unauthorized:         break
            case .scopeInsufficient:    lastError = claudeReauthRequiredMessage
            case .otherError(let e):    lastError = e
            }
        }

        if let creds = cachedCreds {
            switch await fetchClaudeUsage(token: creds.accessToken, plan: plan) {
            case .success(let u):       return u
            case .rateLimited:          lastError = "rate limited"
            case .unauthorized:         break
            // Refresh hands back tokens with the same scope set, so it cannot
            // recover from a missing-scope 403. Bail out and surface the only
            // remediation that actually works.
            case .scopeInsufficient:    return errorPair(claudeReauthRequiredMessage)
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

                switch await fetchClaudeUsage(token: refreshed.accessToken, plan: plan) {
                case .success(let u):       return u
                case .rateLimited:          lastError = "rate limited"
                case .unauthorized:         break
                case .scopeInsufficient:    return errorPair(claudeReauthRequiredMessage)
                case .otherError(let e):    lastError = e
                }
            }
        }

        return errorPair(lastError)
    }

    private enum FetchOutcome {
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

    private static func fetchClaudeUsage(token: String, plan: String?) async -> FetchOutcome {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Anthropic gates this endpoint on a CLI User-Agent. Without it the
        // request 401s even with a valid token.
        req.setValue("claude-code/2.1.121", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .otherError("bad response")
            }
            if http.statusCode == 401 { return .unauthorized }
            if http.statusCode == 403 { return .scopeInsufficient }
            if http.statusCode == 429 { return .rateLimited }
            guard http.statusCode == 200 else {
                return .otherError("HTTP \(http.statusCode)")
            }
            // The endpoint also returns 200 with a rate_limit_error body
            // sometimes; don't trust the status code alone.
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let err = obj["error"] as? [String: Any],
                   let type = err["type"] as? String, type == "rate_limit_error" {
                    return .rateLimited
                }
                return .success(AppUsage(
                    fiveHour: parseClaudeWindow(obj["five_hour"]),
                    weekly: parseClaudeWindow(obj["seven_day"]),
                    plan: plan
                ))
            }
            return .otherError("parse error")
        } catch {
            return .otherError(error.localizedDescription)
        }
    }

    private static func parseClaudeWindow(_ obj: Any?) -> WindowUsage {
        guard let d = obj as? [String: Any] else { return .unknown }
        // Anthropic returns `utilization` as a percentage in [0, 100], not a
        // normalized [0, 1] fraction. An earlier `raw > 1 ? raw / 100 : raw`
        // heuristic broke the moment the 5h window reset: utilization values
        // in (0, 1] (e.g. 0.5% used → 0.5) were treated as already-normalized
        // and rendered as 50%–100%. Always divide by 100; clamp below.
        let raw = (d["utilization"] as? Double) ?? (d["used_percent"] as? Double) ?? 0
        let normalized = raw / 100.0
        var resetAt: Date?
        if let r = d["resets_at"] as? Double {
            resetAt = Date(timeIntervalSince1970: r)
        } else if let s = d["resets_at"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetAt = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        return WindowUsage(usedPercent: min(1, max(0, normalized)), resetAt: resetAt, error: nil)
    }

    // MARK: - Gemini

    /// Gemini usage lives at cloudcode-pa.googleapis.com and accepts
    /// the access_token from ~/.gemini/oauth_creds.json.
    static func fetchGemini() async -> AppUsage {
        guard let token = readGeminiAccessToken() else {
            return errorPair("auth required — run gemini")
        }

        let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["project": "-"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 401 {
                return errorPair("auth expired — gemini login")
            }
            if status != 200 {
                return errorPair("http \(status)")
            }

            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let buckets = obj["buckets"] as? [[String: Any]] else {
                return errorPair("parse error")
            }

            // Find the most relevant model for the UI (Pro for 5h, Flash for weekly as proxy)
            let proBucket = buckets.first { ($0["modelId"] as? String)?.contains("pro") == true }
            let flashBucket = buckets.first { ($0["modelId"] as? String)?.contains("flash") == true }

            return AppUsage(
                fiveHour: parseGeminiBucket(proBucket),
                weekly: parseGeminiBucket(flashBucket),
                plan: "pro"
            )
        } catch {
            return errorPair(error.localizedDescription)
        }
    }

    private static func parseGeminiBucket(_ obj: [String: Any]?) -> WindowUsage {
        guard let d = obj else { return .unknown }
        // remainingFraction is in [0, 1]. usedPercent = 1 - remainingFraction.
        let remaining = (d["remainingFraction"] as? Double) ?? 1.0
        let used = 1.0 - remaining
        
        var resetAt: Date?
        if let s = d["resetTime"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            resetAt = f.date(from: s)
        }
        return WindowUsage(usedPercent: min(1, max(0, used)), resetAt: resetAt, error: nil)
    }

    private static func readGeminiAccessToken() -> String? {
        let path = NSString("~/.gemini/oauth_creds.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else { return nil }

        // Optional: check expiry_date (milliseconds since epoch)
        if let expiry = json["expiry_date"] as? Double {
            let now = Date().timeIntervalSince1970 * 1000
            if now > expiry { return nil }
        }

        return token
    }

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
    static func canPromptClaudeReauth() -> Bool {
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
    static func spawnClaudeReauth() -> Bool {
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
