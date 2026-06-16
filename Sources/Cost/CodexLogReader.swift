import Foundation

/// Walks the local Codex CLI rollout files and emits a TokenEvent for every
/// turn that recorded usage. Mirrors @ccusage/codex's data path:
///   - reads from ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
///   - tracks the most recent `turn_context.payload.model` as the active
///     model for subsequent `event_msg.token_count` events
///   - uses `last_token_usage` (per-turn delta) rather than diffing the
///     accumulating `total_token_usage`, which is a known footgun for
///     forked sessions
///
/// Per-file parse results are memoized in `~/Library/Caches/.../codex-parse-cache.v1.json`
/// keyed by (path, mtime, size). Between two 5/15/30-minute polls almost no
/// rollout file has changed, so the steady-state refresh skips re-parsing.
enum CodexLogReader {
    static func scan(lookbackDays: Int = 30) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        var out: [TokenEvent] = []

        LogParseCache.walk(
            roots: [sessionsRoot()],
            cutoff: cutoff,
            cacheFilename: "codex-parse-cache.v1.json",
            cacheVersion: cacheVersion,
            fileFilter: { $0.lastPathComponent.hasPrefix("rollout-") },
            parse: parseFile(at:),
            emit: { (ev: CachedEvent) in
                guard ev.timestamp >= cutoff else { return }
                out.append(TokenEvent(
                    provider: .codex,
                    timestamp: ev.timestamp,
                    model: ev.model,
                    inputTokens: ev.inputTokens,
                    outputTokens: ev.outputTokens,
                    cacheCreationTokens: 0,
                    cacheReadTokens: ev.cacheReadTokens
                ))
            }
        )
        return out
    }

    private static func sessionsRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("sessions", isDirectory: true)
        }
        return home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// Parse a single file end-to-end. Threads the active model through the
    /// file's lines (Codex sessions can `/model` mid-stream) and emits one
    /// CachedEvent per usage-bearing turn.
    private static func parseFile(at url: URL) -> [CachedEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        var currentModel: String?
        var out: [CachedEvent] = []

        // `maxLineBytes` skips the multi-MB `response_item` blobs (base64
        // screenshots, large tool output) at the reader level — they're never
        // the records we want and assembling them is what stalls big sessions.
        LogParseCache.streamLines(at: url, maxLineBytes: maxUsefulLineBytes) { lineData in
            // The only lines we care about — `turn_context` (model) and
            // `event_msg`/`token_count` (usage) — carry these markers. A cheap
            // byte-scan rejects everything else before paying for JSON parsing.
            guard lineData.range(of: tokenCountMarker) != nil
                    || lineData.range(of: turnContextMarker) != nil else { return }

            guard let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = raw["type"] as? String else { return }

            if type == "turn_context",
               let payload = raw["payload"] as? [String: Any],
               let model = payload["model"] as? String {
                currentModel = model
                return
            }

            guard type == "event_msg",
                  let payload = raw["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any]
            else { return }

            let timestampString = raw["timestamp"] as? String ?? ""
            let timestamp = formatter.date(from: timestampString)
                ?? formatterNoFractional.date(from: timestampString)
                ?? Date.distantPast

            // Codex reports input_tokens INCLUDING the cached portion. Bill
            // the non-cached delta at the input rate and the cached portion
            // at the discounted cache_read rate.
            let totalInput = (last["input_tokens"] as? Int) ?? 0
            let cached = (last["cached_input_tokens"] as? Int) ?? 0
            let nonCachedInput = max(0, totalInput - cached)
            let output = (last["output_tokens"] as? Int) ?? 0

            if nonCachedInput == 0 && cached == 0 && output == 0 { return }

            // Fall back to gpt-5.4 for sessions that emit token_count before
            // any turn_context (early Codex CLI builds did this). Better
            // approximation than billing $0.
            let model = currentModel ?? "gpt-5.4"

            out.append(CachedEvent(
                timestamp: timestamp,
                model: model,
                inputTokens: nonCachedInput,
                outputTokens: output,
                cacheReadTokens: cached
            ))
        }
        return out
    }

    // MARK: - Line pre-filter

    /// Upper bound for a usage/model line. `token_count` payloads are well
    /// under 1KB and even a tool-heavy `turn_context` stays small; 1MB leaves
    /// generous headroom while skipping the multi-MB image/payload lines that
    /// dominate large sessions.
    private static let maxUsefulLineBytes = 1 << 20
    private static let tokenCountMarker = Data("token_count".utf8)
    private static let turnContextMarker = Data("turn_context".utf8)

    // MARK: - Per-file cache

    private static let cacheVersion = 1

    private struct CachedEvent: Codable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
    }
}
