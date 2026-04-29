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
}
