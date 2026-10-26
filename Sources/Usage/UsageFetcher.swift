import Foundation

enum UsageFetcher {
    // MARK: - Codex

    /// Codex usage lives at chatgpt.com/backend-api/wham/usage and accepts
    /// the access_token from ~/.codex/auth.json. The endpoint is reliable
    /// and rarely rate-limited, so this is the easy half of the integration.
    static func fetchCodex(
        credentialData: @autoclosure () -> Data? = nil,
        send: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) async -> AppUsage {
        guard let authData = codexAuthData(credentialData()),
              let req = codexRequest(path: "usage", authData: authData) else {
            return errorPair("no codex auth")
        }
        let accountID = codexAccountID(authData: authData)
        // auth.json can change while the request is in flight; its outcome,
        // success or failure, then describes the old credential.
        func changedCredential() -> AppUsage? {
            // A missing or unusable snapshot (e.g. mid-rewrite) is no credential.
            guard let current = codexAuthData(credentialData()),
                  codexRequest(path: "usage", authData: current) != nil else { return errorPair("no codex auth") }
            // The token identifies a token-only credential; with an account,
            // a same-account CLI token rotation still describes this account.
            guard codexAccountID(authData: current) != accountID
                || (accountID == nil && codexAccessToken(authData: current) != codexAccessToken(authData: authData))
            else { return nil }
            return errorPair("codex credentials changed", accountID: codexAccountID(authData: current), accountResolved: true)
        }

        do {
            let (data, response) = try await send(req)
            if let changed = changedCredential() { return changed }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            // 401 means the access_token in ~/.codex/auth.json has expired.
            // The Codex CLI rotates this token on its own — there's nothing
            // we can do from here, so surface the exact remediation step.
            if status == 401 {
                return errorPair("auth expired — codex login", accountID: accountID, accountResolved: true)
            }
            if status != 200 {
                return errorPair("http \(status)", accountID: accountID, accountResolved: true)
            }

            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rl = obj["rate_limit"] as? [String: Any] else {
                return errorPair("parse error", accountID: accountID, accountResolved: true)
            }
            let windows = routeCodexWindows(rl)
            return AppUsage(
                fiveHour: windows.fiveHour,
                weekly: windows.weekly,
                plan: obj["plan_type"] as? String,
                reportedWindows: windows.reported,
                accountID: accountID,
                accountResolved: true
            )
        } catch {
            if let changed = changedCredential() { return changed }
            return errorPair(error.localizedDescription, accountID: accountID, accountResolved: true)
        }
    }

    /// Pass `accountResolved` once a credential was read, even naming no account.
    private static func errorPair(_ message: String, accountID: String? = nil, accountResolved: Bool = false) -> AppUsage {
        AppUsage(
            fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            monthly: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            fableWeekly: WindowUsage(usedPercent: 0, resetAt: nil, error: message),
            accountID: accountID,
            accountResolved: accountResolved
        )
    }

    private static func codexAuthData(_ credentialData: Data?) -> Data? {
        let authPath = NSString("~/.codex/auth.json").expandingTildeInPath
        return credentialData ?? (try? Data(contentsOf: URL(fileURLWithPath: authPath)))
    }

    private static func codexRequest(path: String, credentialData: Data?) -> URLRequest? {
        guard let data = codexAuthData(credentialData) else { return nil }
        return codexRequest(path: path, authData: data)
    }

    private static func codexAccessToken(authData: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any] else { return nil }
        return tokens["access_token"] as? String
    }

    /// Unfetched usage scoped to the local credential's account, so launch
    /// seeding knows whose history it may show. nil without a usable credential.
    static func codexLocalIdentity(credentialData: Data? = nil) -> AppUsage? {
        guard let data = codexAuthData(credentialData), codexRequest(path: "usage", authData: data) != nil else { return nil }
        return AppUsage(fiveHour: .unknown, weekly: .unknown, accountID: codexAccountID(authData: data), accountResolved: true)
    }

    static func codexAccountID(authData: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accountID = tokens["account_id"] as? String,
              !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return accountID
    }

    static func codexRequest(path: String, authData: Data) -> URLRequest? {
        guard let json = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: "https://chatgpt.com/backend-api/wham/\(path)")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // A token can cover multiple accounts; omitting the selected account
        // lets the backend return another account's quota and reset credits.
        if let accountID = codexAccountID(authData: authData) {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    /// The window slots stopped being positional in mid-2026: plans with a
    /// single weekly limit report it as `primary_window` with
    /// `limit_window_seconds: 604800` and `secondary_window: null`, so
    /// primary→5h / secondary→weekly mislabels the only real reading. Route
    /// each reported window by its advertised span instead — a day cleanly
    /// separates 5h (18000s) from weekly (604800s) — and fall back to slot
    /// order for older shapes that omit `limit_window_seconds`.
    static func routeCodexWindows(_ rl: [String: Any]) -> (fiveHour: WindowUsage, weekly: WindowUsage, reported: [UsageWindow]) {
        var fiveHour: WindowUsage?
        var weekly: WindowUsage?
        let slots: [(key: String, fallback: UsageWindow)] = [
            ("primary_window", .fiveHour),
            ("secondary_window", .weekly),
        ]
        for (key, fallback) in slots {
            guard let d = rl[key] as? [String: Any] else { continue }
            let span = d["limit_window_seconds"] as? Double
            let kind = span.map { $0 >= 86400 ? UsageWindow.weekly : .fiveHour } ?? fallback
            // Same-kind collision: the earlier slot wins. Primary is the
            // provider's headline window — a trailing sibling silently
            // overwriting it would drop the real reading.
            switch kind {
            case .fiveHour: if fiveHour == nil { fiveHour = parseCodexWindow(d) }
            case .weekly:   if weekly == nil { weekly = parseCodexWindow(d) }
            case .monthly, .fableWeekly: break
            }
        }
        var reported: [UsageWindow] = []
        if fiveHour != nil { reported.append(.fiveHour) }
        if weekly != nil { reported.append(.weekly) }
        return (fiveHour ?? .unknown, weekly ?? .unknown, reported)
    }

    private static func parseCodexWindow(_ obj: Any?) -> WindowUsage {
        guard let d = obj as? [String: Any] else { return .unknown }
        let used = (d["used_percent"] as? Double) ?? 0
        let resetAt = (d["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return WindowUsage(usedPercent: used / 100, resetAt: resetAt, error: nil)
    }

    static func fetchCodexResetCredits(
        credentialData: Data? = nil,
        send: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) async -> CodexResetCredits? {
        guard let req = codexRequest(path: "rate-limit-reset-credits", credentialData: credentialData) else { return nil }

        do {
            let (data, response) = try await send(req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            let availableCount = (obj["available_count"] as? Int) ?? 0
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]

            let rawCredits: [[String: Any]] = (obj["credits"] as? [[String: Any]]) ?? []
            let credits: [CodexResetCredit] = rawCredits.compactMap { item -> CodexResetCredit? in
                guard let id = item["id"] as? String,
                      let status = item["status"] as? String,
                      let expiresRaw = item["expires_at"] as? String,
                      let expiresAt = formatter.date(from: expiresRaw)
                        ?? fallbackFormatter.date(from: expiresRaw)
                else { return nil }

                return CodexResetCredit(
                    id: id,
                    status: status,
                    expiresAt: expiresAt,
                    title: item["title"] as? String ?? "",
                    description: item["description"] as? String ?? ""
                )
            }

            return CodexResetCredits(availableCount: availableCount, credits: credits)
        } catch {
            return nil
        }
    }

    // MARK: - Claude

    /// Anthropic doesn't ship a usage endpoint for end users — Claude Code
    /// itself talks to api.anthropic.com/api/oauth/usage with a beta header
    /// and a User-Agent that identifies as the CLI. We replicate that.
    ///
    /// Token acquisition (env → keychain, strictly read-only) lives behind
    /// `ClaudeCredentials`. We hand it the usage probe and render its
    /// resolution: a parsed `AppUsage`, or an error caption (re-auth or last
    /// error) via `errorPair`.
    static func fetchClaude() async -> AppUsage {
        let resolution = await ClaudeCredentials.resolveUsage { token, plan in
            await fetchClaudeUsage(token: token, plan: plan)
        }
        switch resolution {
        case .usage(let u):              return u
        case .reauthRequired(let msg):   return errorPair(msg)
        case .failed(let msg):           return errorPair(msg)
        }
    }

    private static func fetchClaudeUsage(token: String, plan: String?) async -> ClaudeCredentials.ProbeOutcome {
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
                return .success(parseClaudeUsageResponse(obj, plan: plan))
            }
            return .otherError("parse error")
        } catch {
            return .otherError(error.localizedDescription)
        }
    }

    static func parseClaudeUsageResponse(_ object: [String: Any], plan: String?) -> AppUsage {
        let fiveHour = parseClaudeWindow(object["five_hour"])
        let weekly = parseClaudeWindow(object["seven_day"])
        let fableWeekly = parseClaudeFableWindow(object)
        let monthly = parseClaudeEnterpriseCredits(object["extra_usage"])
        var reported: [UsageWindow] = []
        if !fiveHour.isUnreported { reported.append(.fiveHour) }
        if !weekly.isUnreported { reported.append(.weekly) }
        if !fableWeekly.isUnreported { reported.append(.fableWeekly) }
        if monthly != nil { reported.append(.monthly) }
        return AppUsage(fiveHour: fiveHour, weekly: weekly, monthly: monthly ?? .unknown,
                        fableWeekly: fableWeekly,
                        plan: plan, reportedWindows: reported)
    }

    private static func parseClaudeFableWindow(_ object: [String: Any]) -> WindowUsage {
        for limit in object["limits"] as? [[String: Any]] ?? [] {
            guard limit["kind"] as? String == "weekly_scoped",
                  let scope = limit["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String,
                  name.caseInsensitiveCompare("Fable") == .orderedSame
                    || name.lowercased().hasPrefix("fable ") else { continue }
            return parseClaudeWindow(limit)
        }
        return parseClaudeWindow(object["seven_day_overage_included"])
    }

    private static func parseClaudeWindow(_ obj: Any?) -> WindowUsage {
        guard let d = obj as? [String: Any] else { return .unknown }
        // Anthropic returns `utilization` as a percentage in [0, 100], not a
        // normalized [0, 1] fraction. An earlier `raw > 1 ? raw / 100 : raw`
        // heuristic broke the moment the 5h window reset: utilization values
        // in (0, 1] (e.g. 0.5% used → 0.5) were treated as already-normalized
        // and rendered as 50%–100%. Always divide by 100; clamp below.
        guard let raw = (d["utilization"] as? Double) ?? (d["used_percent"] as? Double)
                ?? (d["percent"] as? Double), raw.isFinite else { return .unknown }
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

    static func parseClaudeEnterpriseCredits(_ obj: Any?) -> WindowUsage? {
        guard let details = obj as? [String: Any],
              details["is_enabled"] as? Bool == true,
              let usedCents = details["used_credits"] as? Double,
              usedCents.isFinite, usedCents >= 0 else { return nil }

        // Claude CLI treats these API values as cents (for example, 1600 is
        // displayed as $16.00). Keep raw cents for utilization, then store
        // major currency units for the app's currency formatter.
        guard let rawLimit = details["monthly_limit"] else { return nil }
        let limitCents = rawLimit as? Double
        if !(rawLimit is NSNull), limitCents == nil { return nil }
        guard limitCents.map({ $0.isFinite && $0 >= 0 }) ?? true else { return nil }
        let reportedUtilization = (details["utilization"] as? Double).map { $0 / 100 }
        let utilization: Double
        if limitCents == 0 {
            utilization = 1
        } else {
            utilization = reportedUtilization ?? limitCents.map { usedCents / $0 } ?? 0
        }
        guard utilization.isFinite else { return nil }
        let resetAt: Date?
        if let epoch = details["resets_at"] as? Double, epoch.isFinite {
            resetAt = Date(timeIntervalSince1970: epoch)
        } else if let text = details["resets_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetAt = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        } else {
            resetAt = nil
        }
        return WindowUsage(
            usedPercent: min(1, max(0, utilization)),
            resetAt: resetAt,
            error: nil,
            usedAmount: usedCents / 100,
            limitAmount: limitCents.map { $0 / 100 },
            currencyCode: details["currency"] as? String ?? "USD"
        )
    }
}
