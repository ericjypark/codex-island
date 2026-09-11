import Foundation

enum GrokLogReader {
    struct Record {
        let id: String
        let event: TokenEvent
    }

    static func scan(lookbackDays: Int? = 30, root: URL? = nil, now: Date = Date()) -> LocalCostScan {
        let home = ProcessInfo.processInfo.environment["GROK_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
        let root = root ?? home.appendingPathComponent("sessions", isDirectory: true)
        var result = LocalCostScan()
        guard FileManager.default.fileExists(atPath: root.path) else { return result }
        let cutoff = lookbackDays.map { now.addingTimeInterval(-Double($0) * 86400) } ?? .distantPast
        var records: [String: TokenEvent] = [:]
        let files = LogParseCache.jsonlFiles(under: root, modifiedAfter: cutoff) { $0.lastPathComponent == "updates.jsonl" }
        for file in files {
            guard FileManager.default.isReadableFile(atPath: file.url.path) else {
                result.unreadableFiles += 1
                continue
            }
            var found = false
            LogParseCache.streamLines(at: file.url, maxLineBytes: 2_097_152) { data in
                for record in parse(data) where record.event.timestamp >= cutoff && record.event.timestamp <= now {
                    // Final prompt usage can be repeated in persisted ACP updates.
                    records[record.id] = record.event
                    found = true
                }
            }
            if !found { result.skippedRecords += 1 }
        }
        result.events = Array(records.values)
        return result
    }

    static func parse(_ data: Data) -> [Record] {
        guard let row = try? JSONDecoder().decode(Update.self, from: data) else { return [] }
        let meta = row._meta ?? row.update?._meta ?? row.params?.update?._meta
        guard let meta, meta.usageIsIncomplete != true,
              let prompt = meta.promptId, !prompt.isEmpty,
              let timestamp = row.timestamp?.date ?? meta.timestamp?.date,
              let models = meta.modelUsage ?? meta.usage?.modelUsage else { return [] }
        return models.compactMap { model, usage in
            guard !model.isEmpty, usage.costIsPartial != true,
                  let fullInput = usage.inputTokens, let output = usage.outputTokens else { return nil }
            let cacheRead = usage.cacheReadTokens ?? 0
            let cacheWrite = usage.cacheCreationTokens ?? 0
            guard [fullInput, output, cacheRead, cacheWrite].allSatisfy({ $0 >= 0 && $0 <= 1_000_000_000 }),
                  fullInput >= cacheRead + cacheWrite, fullInput + output > 0 else { return nil }
            // ACP PromptUsage input includes cache; TokenEvent buckets are disjoint.
            return Record(id: "\(prompt):\(model)", event: TokenEvent(provider: .grok,
                timestamp: timestamp, model: model, inputTokens: fullInput - cacheRead - cacheWrite,
                outputTokens: output, cacheCreationTokens: cacheWrite, cacheReadTokens: cacheRead,
                recordID: "\(prompt):\(model)"))
        }
    }

    private struct Update: Decodable {
        let timestamp: Timestamp?
        let _meta: Meta?
        let update: NestedUpdate?
        let params: Parameters?
    }
    private struct NestedUpdate: Decodable { let _meta: Meta? }
    private struct Parameters: Decodable { let update: NestedUpdate? }
    private struct Meta: Decodable {
        let timestamp: Timestamp?
        let promptId: String?
        let usageIsIncomplete: Bool?
        let usage: Usage?
        let modelUsage: [String: ModelUsage]?
    }
    private struct Usage: Decodable { let modelUsage: [String: ModelUsage]? }
    private struct ModelUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadTokens: Int?
        let cacheCreationTokens: Int?
        let costIsPartial: Bool?
    }
    private struct Timestamp: Decodable {
        let date: Date?
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let text = try? value.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatter.date(from: text) { date = parsed; return }
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: text)
            } else if let number = try? value.decode(Double.self), number.isFinite, number > 0 {
                date = Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
            } else { date = nil }
        }
    }
}
