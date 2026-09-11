import Foundation
import SQLite3

enum L10n {
    static let locale = Locale(identifier: "en_US")
    static func tr(_ text: String, _ args: CVarArg...) -> String { String(format: text, arguments: args) }
}

@main
struct LocalProviderCostTests {
    static func expect(_ result: Bool, _ label: String) {
        guard result else { print("FAIL \(label)"); exit(1) }
        print("PASS \(label)")
    }
    static func varint(_ n: UInt64) -> Data {
        var n = n, out = Data()
        while n >= 128 { out.append(UInt8(n & 127) | 128); n >>= 7 }
        out.append(UInt8(n)); return out
    }
    static func integer(_ field: Int, _ value: Int) -> Data {
        varint(UInt64(field << 3)) + varint(UInt64(value))
    }
    static func bytes(_ field: Int, _ value: Data) -> Data {
        varint(UInt64(field << 3 | 2)) + varint(UInt64(value.count)) + value
    }
    static func generation(id: String = "call-1", model: String = "gemini-3.8-flash") -> Data {
        let usage = integer(2, 1000) + integer(3, 200) + integer(5, 4000)
            + integer(9, 120) + integer(10, 80) + bytes(7, Data(id.utf8))
        let chat = bytes(4, usage) + bytes(19, Data(model.utf8))
        return bytes(1, chat) + bytes(2, Data([1, 2]))
    }
    static func createDB(_ path: URL, date: Date) {
        var db: OpaquePointer?
        expect(sqlite3_open(path.path, &db) == SQLITE_OK, "create isolated fixture")
        defer { sqlite3_close(db) }
        let metadata = bytes(1, integer(1, Int(date.timeIntervalSince1970)))
        func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
        let sql = """
        CREATE TABLE steps(idx INTEGER, metadata BLOB);
        CREATE TABLE gen_metadata(idx INTEGER, data BLOB);
        INSERT INTO steps VALUES(1, X'\(hex(metadata))'),(2, X'\(hex(metadata))');
        INSERT INTO gen_metadata VALUES(0, X'\(hex(generation()))');
        """
        expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "write metadata fixture")
    }
    static func main() throws {
        let now = ISO8601DateFormatter().date(from: "2026-09-08T18:00:00Z") ?? Date()
        let record = AntigravityLogReader.record(generation: generation(), stepDates: [1: now, 2: now], fallbackID: "fallback")
        expect(record?.event.inputTokens == 1000 && record?.event.cacheReadTokens == 4000, "agy cache and uncached input stay disjoint")
        expect(record?.event.outputTokens == 200, "thinking is not added to output twice")
        expect(record?.event.model == "gemini-3.8-flash", "model identity comes from response")
        expect(AntigravityLogReader.record(generation: generation(), stepDates: [:], fallbackID: "x") == nil, "missing timestamp never assigned to today")
        expect(ProtobufFields(Data([10, 8, 1])) == nil, "truncated protobuf rejected")
        expect(ProtobufFields(Data(repeating: 255, count: 12)) == nil, "overflowing varint rejected")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        createDB(dir.appendingPathComponent("a.db"), date: now.addingTimeInterval(-3600))
        try FileManager.default.copyItem(at: dir.appendingPathComponent("a.db"), to: dir.appendingPathComponent("fork.db"))
        let scan = AntigravityLogReader.scan(lookbackDays: 10, root: dir, now: now)
        expect(scan.events.count == 1, "forked database and multiple steps count one model call")
        expect(scan.notice == nil, "successful local scan is complete")
        let summary = CostSummary.summarize(events: scan.events, now: now)
        expect(summary.today.tokens == 5200 && summary.month.tokens == 5200, "new provider feeds existing today and month totals")
        expect(summary.dailyTokens.reduce(0) { $0 + $1.tokens } == 5200, "new provider feeds activity history")
        expect(summary.recentByModel.first?.tokens == 1200, "model breakdown uses common billable token rule")
        expect(abs(summary.today.dollars - 0.0018) < 0.0000001, "Gemini public rates include cache discount")
        let future = AntigravityLogReader.scan(lookbackDays: 10, root: dir, now: now.addingTimeInterval(-7200))
        expect(future.events.isEmpty, "future-dated calls excluded")
        try Data("not sqlite".utf8).write(to: dir.appendingPathComponent("broken.db"))
        let partial = AntigravityLogReader.scan(lookbackDays: 10, root: dir, now: now)
        expect(partial.events.count == 1 && partial.unreadableFiles == 1, "unreadable database keeps readable records with warning")
        let grok = Data("""
        {"timestamp":"2026-09-08T17:00:00Z","_meta":{"promptId":"prompt-1","modelUsage":{"grok-test":{"inputTokens":5000,"outputTokens":200,"cacheReadTokens":4000,"cacheCreationTokens":0}}}}
        """.utf8)
        let parsed = GrokLogReader.parse(grok)
        expect(parsed.first?.event.inputTokens == 1000 && parsed.first?.event.cacheReadTokens == 4000, "ACP full prompt is normalized to disjoint buckets")
        let stream = dir.appendingPathComponent("updates.jsonl")
        try (grok + Data([10]) + grok + Data([10])).write(to: stream)
        expect(GrokLogReader.scan(root: dir, now: now).events.count == 1, "repeated Grok prompt totals deduplicated")
        let nextYear = now.addingTimeInterval(400 * 86400)
        expect(AntigravityLogReader.scan(root: dir, now: nextYear).events.isEmpty
            && AntigravityLogReader.scan(lookbackDays: nil, root: dir, now: nextYear).events.count == 1,
               "all-time Antigravity scan includes records outside the normal lookback")
        expect(GrokLogReader.scan(root: dir, now: nextYear).events.isEmpty
            && GrokLogReader.scan(lookbackDays: nil, root: dir, now: nextYear).events.count == 1,
               "all-time Grok scan includes records outside the normal lookback")
        let incomplete = Data(String(decoding: grok, as: UTF8.self).replacingOccurrences(of: "\"promptId\"", with: "\"usageIsIncomplete\":true,\"promptId\"").utf8)
        expect(GrokLogReader.parse(incomplete).isEmpty, "incomplete Grok aggregate never presented as complete cost")
        expect(Pricing.canonicalModelName("claude-opus-4-6-thinking") == "claude-opus-4-6", "Antigravity thinking alias shares base model pricing")
        if let event = record?.event {
            let later = TokenEvent(provider: .antigravity, timestamp: Date(timeIntervalSince1970: 1_798_761_600), model: event.model,
                inputTokens: event.inputTokens, outputTokens: event.outputTokens, cacheCreationTokens: 0, cacheReadTokens: event.cacheReadTokens)
            expect(abs(Pricing.cost(for: later) - 0.0036) < 0.0000001, "Gemini introductory rate ends at documented boundary")
        }
    }
}
