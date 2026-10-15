import Foundation

/// Walks the local Claude Code session JSONL files and emits TokenEvents for
/// every assistant message that recorded usage:
///   - reads from ~/.claude/projects/**/*.jsonl AND ~/.config/claude/projects/**/*.jsonl
///   - honors CLAUDE_CONFIG_DIR (comma-separated) when set
///   - includes locally mirrored Cowork project logs in the default search
///   - dedupes by `messageId:requestId`
///   - skips synthetic placeholder models
///
/// Per-file parse results are memoized in `~/Library/Caches/.../claude-parse-cache.v1.json`
/// keyed by (path, mtime, size). Between two 5/15/30-minute polls almost no
/// file has changed, so the steady-state refresh skips the JSONL scan entirely
/// and only walks the events list to dedup + filter by cutoff.
enum ClaudeLogReader {
    /// Walk the configured project roots and return every usage-bearing
    /// assistant turn from the last `lookbackDays` days. Pure file IO; no
    /// network. Safe to call from a background thread.
    static func scan(lookbackDays: Int? = 30, roots: [URL]? = nil, requireStableIDs: Bool = false) -> [TokenEvent] {
        let cutoff = lookbackDays.map { Date().addingTimeInterval(-Double($0) * 86400) } ?? .distantPast
        var positions: [String: Int] = [:]
        var occurrences: [String: Int] = [:]
        var out: [TokenEvent] = []

        LogParseCache.walk(
            roots: roots ?? projectRoots(),
            cutoff: cutoff,
            cacheFilename: "claude-parse-cache.v1.json",
            cacheVersion: cacheVersion,
            useCache: roots == nil,
            parse: parseFile(at:),
            emit: { (ev: CachedEvent, file: URL) in
                guard ev.timestamp >= cutoff, !requireStableIDs || !ev.dedupKey.isEmpty else { return }
                let event = TokenEvent(
                    provider: .claude,
                    timestamp: ev.timestamp,
                    model: ev.model,
                    inputTokens: ev.inputTokens,
                    outputTokens: ev.outputTokens,
                    cacheCreationTokens: ev.cacheCreationTokens,
                    cacheReadTokens: ev.cacheReadTokens,
                    recordID: ev.dedupKey.isEmpty
                        ? LogParseCache.recordID(file: file, timestamp: ev.timestamp, occurrences: &occurrences)
                        : ev.dedupKey
                )
                if !ev.dedupKey.isEmpty, let position = positions[ev.dedupKey] {
                    let previous = out[position]
                    // Streaming rows can repeat a call with more complete usage. Keep an actual row, never a synthetic sum.
                    if event.model == previous.model,
                       event.inputTokens >= previous.inputTokens, event.outputTokens >= previous.outputTokens,
                       event.cacheCreationTokens >= previous.cacheCreationTokens, event.cacheReadTokens >= previous.cacheReadTokens {
                        out[position] = event
                    }
                } else {
                    if !ev.dedupKey.isEmpty { positions[ev.dedupKey] = out.count }
                    out.append(event)
                }
            }
        )
        return out
    }

    static func projectRoots() -> [URL] {
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
        ].filter { FileManager.default.fileExists(atPath: $0.path) } + desktopProjectRoots(home: home)
    }

    private static func desktopProjectRoots(home: URL) -> [URL] {
        let root = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: [.isDirectoryKey],
                                                              options: [.skipsPackageDescendants]) else { return [] }
        var roots: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "projects"
            && url.deletingLastPathComponent().lastPathComponent == ".claude" {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            roots.append(url)
            enumerator.skipDescendants()
        }
        return roots
    }

    /// Parse a single file end-to-end. Caller is responsible for cutoff
    /// filtering — the cache keeps everything we found so a later scan with
    /// a wider window doesn't have to re-read.
    private static func parseFile(at url: URL) -> [CachedEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        var out: [CachedEvent] = []
        LogParseCache.streamLines(at: url) { lineData in
            if let event = parseLine(
                lineData,
                formatter: formatter,
                formatterNoFractional: formatterNoFractional
            ) {
                out.append(event)
            }
        }
        return out
    }

    /// Returns nil for non-assistant rows, synthetic placeholder models,
    /// noop usage entries, and lines that fail to parse.
    private static func parseLine(
        _ lineData: Data,
        formatter: ISO8601DateFormatter,
        formatterNoFractional: ISO8601DateFormatter
    ) -> CachedEvent? {
        guard let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
        else { return nil }

        // Only assistant messages carry usage. The shape is consistent
        // across Claude Code versions: top-level `type == "assistant"`,
        // `message.usage`, `message.model`, `message.id`, top-level
        // `requestId`, top-level `timestamp`.
        guard (raw["type"] as? String) == "assistant",
              let message = raw["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String
        else { return nil }

        // Skip synthetic placeholder models (ccusage parity).
        if model == "<synthetic>" || model.hasPrefix("synthetic") { return nil }

        let messageId = message["id"] as? String ?? ""
        let requestId = raw["requestId"] as? String ?? ""

        // ccusage requires BOTH IDs for dedup; entries missing either
        // are processed without dedup. Match that behavior so a partial
        // log doesn't silently drop turns.
        let dedupKey = (messageId.isEmpty || requestId.isEmpty)
            ? ""
            : "\(messageId):\(requestId)"

        let timestampString = raw["timestamp"] as? String ?? ""
        let timestamp = formatter.date(from: timestampString)
            ?? formatterNoFractional.date(from: timestampString)
            ?? Date.distantPast

        let input = (usage["input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

        // Skip noop entries — ccusage filters these so totals match exactly.
        if input == 0 && output == 0 && cacheCreate == 0 && cacheRead == 0 { return nil }

        return CachedEvent(
            timestamp: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            dedupKey: dedupKey
        )
    }

    // MARK: - Per-file cache

    /// Bump on any breaking change to `CachedEvent` to force a clean re-parse.
    private static let cacheVersion = 1

    private struct CachedEvent: Codable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
        let dedupKey: String
    }
}
