import Foundation

/// Walks the local Codex CLI rollout files and emits a TokenEvent for every
/// turn that recorded usage. Mirrors @ccusage/codex's data path:
///   - reads from ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
///   - tracks the most recent `turn_context.payload.model` as the active
///     model for subsequent `event_msg.token_count` events
///   - uses `last_token_usage` (per-turn delta) rather than diffing the
///     accumulating `total_token_usage`, which is a known footgun for
///     forked sessions
enum CodexLogReader {
    static func scan(lookbackDays: Int = 30) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        var out: [TokenEvent] = []

        for file in jsonlFiles(under: sessionsRoot(), modifiedAfter: cutoff) {
            parseFile(at: file, cutoff: cutoff, into: &out)
        }
        return out
    }

    private static func sessionsRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("sessions", isDirectory: true)
        }
        return home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    private static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return [] }

        var hits: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-") else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            if let mtime = values?.contentModificationDate, mtime < cutoff { continue }
            hits.append(url)
        }
        return hits
    }

    private static func parseFile(at url: URL, cutoff: Date, into out: inout [TokenEvent]) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        // Codex rollouts can switch models mid-session via `/model`. Track
        // the most recent `turn_context.payload.model` and attribute each
        // following token_count event to it.
        var currentModel: String?

        // Manual newline split rather than `enumerateLines` — its closure is
        // escaping and can't capture our inout `out` buffer or the
        // `currentModel` we're threading through the file.
        for line in text.split(whereSeparator: { $0.isNewline }) {
            guard let lineData = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = raw["type"] as? String else { continue }

            if type == "turn_context",
               let payload = raw["payload"] as? [String: Any],
               let model = payload["model"] as? String {
                currentModel = model
                continue
            }

            guard type == "event_msg",
                  let payload = raw["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any]
            else { continue }

            let timestampString = raw["timestamp"] as? String ?? ""
            let timestamp = formatter.date(from: timestampString)
                ?? formatterNoFractional.date(from: timestampString)
                ?? Date.distantPast
            guard timestamp >= cutoff else { continue }

            // Codex reports input_tokens INCLUDING the cached portion. Bill
            // the non-cached delta at the input rate and the cached portion
            // at the discounted cache_read rate.
            let totalInput = (last["input_tokens"] as? Int) ?? 0
            let cached = (last["cached_input_tokens"] as? Int) ?? 0
            let nonCachedInput = max(0, totalInput - cached)
            let output = (last["output_tokens"] as? Int) ?? 0

            if nonCachedInput == 0 && cached == 0 && output == 0 { continue }

            // Fall back to gpt-5.4 for sessions that emit token_count before
            // any turn_context (early Codex CLI builds did this). Better
            // approximation than billing $0.
            let model = currentModel ?? "gpt-5.4"

            out.append(TokenEvent(
                provider: .codex,
                timestamp: timestamp,
                model: model,
                inputTokens: nonCachedInput,
                outputTokens: output,
                cacheCreationTokens: 0,
                cacheReadTokens: cached
            ))
        }
    }
}
