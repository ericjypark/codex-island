import Foundation

// Mocking LogParseCache and TokenEvent to test GeminiLogReader logic.
// This is more of a unit test but runs against real local logs.

struct TokenEvent {
    enum Provider { case gemini }
    let provider: Provider
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
}

enum GeminiLogReader {
    static func scan() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let geminiDir = home.appendingPathComponent(".gemini", isDirectory: true)
        let roots = [
            geminiDir.appendingPathComponent("tmp", isDirectory: true),
            geminiDir.appendingPathComponent("history", isDirectory: true)
        ].filter { FileManager.default.fileExists(atPath: $0.path) }

        print("📂 Scanning roots: \(roots.map { $0.path })")
        
        for root in roots {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                if url.lastPathComponent.hasSuffix(".jsonl") {
                    parseFile(at: url)
                }
            }
        }
    }

    private static func parseFile(at url: URL) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFractional = ISO8601DateFormatter()
        formatterNoFractional.formatOptions = [.withInternetDateTime]

        guard let content = try? String(contentsOf: url) else { return }
        let lines = content.split(separator: "\n")
        
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = raw["type"] as? String, type == "gemini",
                  let tokens = raw["tokens"] as? [String: Any],
                  let model = raw["model"] as? String else { continue }

            let timestampString = raw["timestamp"] as? String ?? ""
            let timestamp = formatter.date(from: timestampString)
                ?? formatterNoFractional.date(from: timestampString)
                ?? Date.distantPast

            let input = (tokens["input"] as? Int) ?? 0
            let output = (tokens["output"] as? Int) ?? 0
            let cached = (tokens["cached"] as? Int) ?? 0

            print("✅ Found usage: \(model) | In: \(input) | Out: \(output) | Cache: \(cached) | at \(timestamp)")
        }
    }
}

print("🚀 Testing Gemini Log Reader...")
GeminiLogReader.scan()
