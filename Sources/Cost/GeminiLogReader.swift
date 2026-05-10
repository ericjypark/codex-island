import Foundation

/// Walks the local Gemini session JSONL files and emits a TokenEvent for every
/// turn that recorded usage.
enum GeminiLogReader {
    static func scan(lookbackDays: Int = 30) -> [TokenEvent] {
        let cutoff = Date().addingTimeInterval(-Double(lookbackDays) * 86400)
        var latestById: [String: TokenEvent] = [:]
        var withoutId: [TokenEvent] = []

        let home = FileManager.default.homeDirectoryForCurrentUser
        let geminiDir = home.appendingPathComponent(".gemini", isDirectory: true)
        let roots = [
            geminiDir.appendingPathComponent("tmp", isDirectory: true),
            geminiDir.appendingPathComponent("history", isDirectory: true)
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        LogParseCache.walk(
            roots: roots,
            cutoff: cutoff,
            cacheFilename: "gemini-parse-cache.v1.json",
            cacheVersion: cacheVersion,
            fileFilter: { $0.lastPathComponent.hasSuffix(".jsonl") },
            parse: parseFile(at:),
            emit: { (ev: CachedEvent) in
                guard ev.timestamp >= cutoff else { return }
                let event = TokenEvent(
                    provider: .gemini,
                    timestamp: ev.timestamp,
                    model: ev.model,
                    inputTokens: ev.inputTokens,
                    outputTokens: ev.outputTokens,
                    cacheCreationTokens: ev.cacheCreationTokens,
                    cacheReadTokens: ev.cacheReadTokens
                )
                if !ev.dedupKey.isEmpty {
                    // Overwrite earlier events for the same ID to capture the
                    // final turn state (which has the complete output tokens).
                    latestById[ev.dedupKey] = event
                } else {
                    withoutId.append(event)
                }
            }
        )
        
        let allEvents = Array(latestById.values) + withoutId
        return allEvents.sorted { $0.timestamp < $1.timestamp }
    }

    private static func parseFile(at url: URL) -> [CachedEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        var out: [CachedEvent] = []
        LogParseCache.streamLines(at: url) { lineData in
            guard let raw = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = raw["type"] as? String, type == "gemini",
                  let tokens = raw["tokens"] as? [String: Any],
                  let model = raw["model"] as? String else { return }

            let id = raw["id"] as? String ?? ""
            let timestampString = raw["timestamp"] as? String ?? ""
            let timestamp = formatter.date(from: timestampString)
                ?? formatterNoFractional.date(from: timestampString)
                ?? Date.distantPast

            let input = (tokens["input"] as? Int) ?? 0
            let output = (tokens["output"] as? Int) ?? 0
            let cached = (tokens["cached"] as? Int) ?? 0

            // Gemini API reports 'input' as the TOTAL input tokens (including cached).
            // The cost pipeline expects inputTokens to be the UNCACHED portion.
            let billableInput = max(0, input - cached)

            if billableInput == 0 && output == 0 && cached == 0 { return }

            out.append(CachedEvent(
                timestamp: timestamp,
                model: model,
                inputTokens: billableInput,
                outputTokens: output,
                cacheCreationTokens: 0,
                cacheReadTokens: cached,
                dedupKey: id
            ))
        }
        return out
    }

    // MARK: - Per-file cache

    private static let cacheVersion = 4

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
