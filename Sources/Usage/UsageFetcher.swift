import Foundation

enum UsageFetcher {
    // MARK: - Codex

    /// Codex usage lives at chatgpt.com/backend-api/wham/usage and accepts
    /// the access_token from ~/.codex/auth.json. The endpoint is reliable
    /// and rarely rate-limited, so this is the easy half of the integration.
    static func fetchCodex() async -> AppUsage {
        guard let token = readCodexAccessToken() else {
            return AppUsage(
                fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: "no codex auth"),
                weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: "no codex auth")
            )
        }

        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rl = obj["rate_limit"] as? [String: Any] else {
                return AppUsage(
                    fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: "parse error"),
                    weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: "parse error")
                )
            }
            return AppUsage(
                fiveHour: parseCodexWindow(rl["primary_window"]),
                weekly: parseCodexWindow(rl["secondary_window"])
            )
        } catch {
            return AppUsage(
                fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: error.localizedDescription),
                weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: error.localizedDescription)
            )
        }
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
    ///   3. console.anthropic.com/v1/oauth/token refresh — Anthropic
    ///      rotates the refresh_token on every call (the response carries
    ///      a new pair). We must persist that new pair back to the keychain
    ///      via writeClaudeCreds, otherwise Claude Code itself 401s on its
    ///      next refresh because the keychain still holds the now-revoked
    ///      old token.
    static func fetchClaude() async -> AppUsage {
        var lastError = "auth required — run claude"

        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            switch await fetchClaudeUsage(token: envToken) {
            case .success(let u):       return u
            case .rateLimited:          lastError = "rate limited"
            case .unauthorized:         break
            case .otherError(let e):    lastError = e
            }
        }

        if let creds = readClaudeCreds() {
            switch await fetchClaudeUsage(token: creds.accessToken) {
            case .success(let u):       return u
            case .rateLimited:          lastError = "rate limited"
            case .unauthorized:         break
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

                switch await fetchClaudeUsage(token: refreshed.accessToken) {
                case .success(let u):       return u
                case .rateLimited:          lastError = "rate limited"
                case .unauthorized:         break
                case .otherError(let e):    lastError = e
                }
            }
        }

        return AppUsage(
            fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: lastError),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: lastError)
        )
    }

    private enum FetchOutcome {
        case success(AppUsage)
        case rateLimited
        case unauthorized
        case otherError(String)
    }

    private struct ClaudeCreds {
        let account: String
        let accessToken: String
        let refreshToken: String
        let oauth: [String: Any]
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
            return ClaudeCreds(account: account, accessToken: access, refreshToken: refresh, oauth: oauth)
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

    private static func fetchClaudeUsage(token: String) async -> FetchOutcome {
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
                    weekly: parseClaudeWindow(obj["seven_day"])
                ))
            }
            return .otherError("parse error")
        } catch {
            return .otherError(error.localizedDescription)
        }
    }

    private static func parseClaudeWindow(_ obj: Any?) -> WindowUsage {
        guard let d = obj as? [String: Any] else { return .unknown }
        let raw = (d["utilization"] as? Double) ?? (d["used_percent"] as? Double) ?? 0
        let normalized = raw > 1 ? raw / 100 : raw
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
        var req = URLRequest(url: URL(string: "https://console.anthropic.com/v1/oauth/token")!)
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
}
