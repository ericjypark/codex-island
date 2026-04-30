import Foundation

/// Walks the local Claude Code session JSONL files and emits TokenEvents for
/// every assistant message that recorded usage. Mirrors ccusage's data path:
///   - reads from ~/.claude/projects/**/*.jsonl AND ~/.config/claude/projects/**/*.jsonl
///   - honors CLAUDE_CONFIG_DIR (comma-separated) when set
///   - dedupes by `messageId:requestId`
///   - skips synthetic placeholder models
enum ClaudeLogReader {
    /// Walk the configured project roots and return every usage-bearing
    /// assistant turn from the last `lookbackDays` days. Pure file IO; no
    /// network. Safe to call from a background thread.
    static func scan(lookbackDays: Int = 30) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        var seen = Set<String>()
        var out: [TokenEvent] = []

        for root in projectRoots() {
            for file in jsonlFiles(under: root, modifiedAfter: cutoff) {
                parseFile(at: file, cutoff: cutoff, seen: &seen, into: &out)
            }
        }
        return out
    }

    private static func projectRoots() -> [URL] {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            return env.split(separator: ",").map {
                URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces))
                    .appendingPathComponent("projects", isDirectory: true)
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var hits: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            if let mtime = values?.contentModificationDate, mtime < cutoff { continue }
            hits.append(url)
        }
        return hits
    }

    private static func parseFile(
        at url: URL,
        cutoff: Date,
        seen: inout Set<String>,
        into out: inout [TokenEvent]
    ) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        // Manual newline split rather than `enumerateLines` — its closure is
        // escaping and can't capture our inout dedup/output buffers.
        for line in text.split(whereSeparator: { $0.isNewline }) {
            guard let lineData = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            // Only assistant messages carry usage. The shape is consistent
            // across Claude Code versions: top-level `type == "assistant"`,
            // `message.usage`, `message.model`, `message.id`, top-level
            // `requestId`, top-level `timestamp`.
            guard (raw["type"] as? String) == "assistant",
                  let message = raw["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let model = message["model"] as? String
            else { continue }

            // Skip synthetic placeholder models (ccusage parity).
            if model == "<synthetic>" || model.hasPrefix("synthetic") { continue }

            let messageId = message["id"] as? String ?? ""
            let requestId = raw["requestId"] as? String ?? ""

            // ccusage requires BOTH IDs for dedup; entries missing either
            // are processed without dedup. Match that behavior so a partial
            // log doesn't silently drop turns.
            if !messageId.isEmpty && !requestId.isEmpty {
                let key = "\(messageId):\(requestId)"
                if seen.contains(key) { continue }
                seen.insert(key)
            }

            let timestampString = raw["timestamp"] as? String ?? ""
            let timestamp = formatter.date(from: timestampString)
                ?? formatterNoFractional.date(from: timestampString)
                ?? Date.distantPast
            guard timestamp >= cutoff else { continue }

            let input = (usage["input_tokens"] as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

            // Skip noop entries — ccusage filters these so totals match exactly.
            if input == 0 && output == 0 && cacheCreate == 0 && cacheRead == 0 { continue }

            out.append(TokenEvent(
                provider: .claude,
                timestamp: timestamp,
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cacheCreate,
                cacheReadTokens: cacheRead
            ))
        }
    }
}
