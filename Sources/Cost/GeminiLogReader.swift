import Foundation

/// Walks the local Gemini session JSONL files and emits a TokenEvent for every
/// turn that recorded usage.
enum GeminiLogReader {
    static func scan(lookbackDays: Int = 30) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        var out: [TokenEvent] = []

        LogParseCache.walk(
            roots: [logsRoot()],
            cutoff: cutoff,
            cacheFilename: "gemini-parse-cache.v1.json",
            cacheVersion: cacheVersion,
            fileFilter: { $0.lastPathComponent.hasSuffix(".jsonl") },
            parse: parseFile(at:),
            emit: { (ev: CachedEvent) in
                guard ev.timestamp >= cutoff else { return }
                out.append(TokenEvent(
                    provider: .gemini,
                    timestamp: ev.timestamp,
                    model: ev.model,
                    inputTokens: ev.inputTokens,
                    outputTokens: ev.outputTokens,
                    cacheCreationTokens: ev.cacheCreationTokens,
                    cacheReadTokens: ev.cacheReadTokens
                ))
            }
        )
        return out
    }

    private static func logsRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let geminiHome = ProcessInfo.processInfo.environment["GEMINI_HOME"], !geminiHome.isEmpty {
            return URL(fileURLWithPath: geminiHome).appendingPathComponent("logs", isDirectory: true)
        }
        return home.appendingPathComponent(".gemini/logs", isDirectory: true)
    }

    private static func parseFile(at url: URL) -> [CachedEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        var out: [CachedEvent] = []
        LogParseCache.streamLines(at: url) { lineData in
            guard let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = raw["type"] as? String, type == "usage",
                  let usage = raw["usage"] as? [String: Any],
                  let model = raw["model"] as? String else { return }

            let timestampString = raw["timestamp"] as? String ?? ""
            let timestamp = formatter.date(from: timestampString)
                ?? formatterNoFractional.date(from: timestampString)
                ?? Date.distantPast

            let input = (usage["input_tokens"] as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_tokens"] as? Int) ?? 0

            if input == 0 && output == 0 && cacheCreate == 0 && cacheRead == 0 { return }

            out.append(CachedEvent(
                timestamp: timestamp,
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheCreationTokens: cacheCreate,
                cacheReadTokens: cacheRead
            ))
        }
        return out
    }

    // MARK: - Per-file cache

    private static let cacheVersion = 1

    private struct CachedEvent: Codable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int
    }
}
