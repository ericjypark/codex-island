import Foundation
import SQLite3

enum AntigravityLogReader {
    struct Record {
        let id: String
        let event: TokenEvent
    }

    static func scan(lookbackDays: Int? = 30, root: URL? = nil, now: Date = Date()) -> LocalCostScan {
        let root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/conversations", isDirectory: true)
        var result = LocalCostScan()
        guard FileManager.default.fileExists(atPath: root.path) else { return result }
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            result.unreadableFiles = 1
            return result
        }
        let cutoff = lookbackDays.map { now.addingTimeInterval(-Double($0) * 86400) } ?? .distantPast
        var seen = Set<String>()
        for file in files.filter({ $0.pathExtension == "db" }).sorted(by: { $0.path < $1.path }) {
            do {
                let records = try read(file)
                result.skippedRecords += records.skipped
                for record in records.records where record.event.timestamp >= cutoff && record.event.timestamp <= now {
                    if seen.insert(record.id).inserted { result.events.append(record.event) }
                }
            } catch { result.unreadableFiles += 1 }
        }
        return result
    }

    // One gen_metadata row is one model call. A call can produce several steps;
    // summing steps or transcript/chunk copies would count the same call repeatedly.
    static func record(generation: Data, stepDates: [Int: Date], fallbackID: String) -> Record? {
        guard let gen = ProtobufFields(generation), let chat = gen.message(1),
              let usage = chat.message(4), let indices = gen.integers(2),
              let date = indices.compactMap({ stepDates[$0] }).min() else { return nil }
        let input = usage.integer(2) ?? 0
        let output = usage.integer(3) ?? 0
        let cacheWrite = usage.integer(4) ?? 0
        let cacheRead = usage.integer(5) ?? 0
        // ModelUsageStats already separates cache input and includes thinking in output.
        guard [input, output, cacheWrite, cacheRead].allSatisfy({ $0 <= 1_000_000_000 }),
              input + output + cacheWrite + cacheRead > 0 else { return nil }
        let rawModel = chat.string(19) ?? chat.string(22) ?? chat.string(21)
        let model = rawModel.flatMap { $0.isEmpty ? nil : $0 } ?? "antigravity-model-\(chat.integer(3) ?? 0)"
        let messageID = usage.string(12) ?? usage.string(7) ?? usage.string(11)
        let id = messageID.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackID
        return Record(id: id, event: TokenEvent(provider: .antigravity, timestamp: date,
            model: model, inputTokens: input, outputTokens: output,
            cacheCreationTokens: cacheWrite, cacheReadTokens: cacheRead, recordID: id))
    }

    private enum ReadError: Error { case database }

    private static func read(_ file: URL) throws -> (records: [Record], skipped: Int) {
        var pointer: OpaquePointer?
        let status = sqlite3_open_v2(file.path, &pointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK, let db = pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw ReadError.database
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw ReadError.database }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var dates: [Int: Date] = [:]
        try rows(db, sql: "SELECT idx, metadata FROM steps") { index, data in
            if let metadata = ProtobufFields(data), let date = metadata.message(1)?.timestamp {
                dates[index] = date
            }
        }
        var records: [Record] = []
        var skipped = 0
        try rows(db, sql: "SELECT idx, data FROM gen_metadata") { index, data in
            if let record = record(generation: data, stepDates: dates,
                                   fallbackID: "\(file.deletingPathExtension().lastPathComponent):\(index)") {
                records.append(record)
            } else if ProtobufFields(data)?.message(1) != nil {
                skipped += 1
            }
        }
        return (records, skipped)
    }

    private static func rows(_ db: OpaquePointer, sql: String, consume: (Int, Data) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ReadError.database
        }
        defer { sqlite3_finalize(statement) }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return }
            guard status == SQLITE_ROW else { throw ReadError.database }
            let count = Int(sqlite3_column_bytes(statement, 1))
            guard count <= 16_777_216, let bytes = sqlite3_column_blob(statement, 1) else { continue }
            consume(Int(sqlite3_column_int64(statement, 0)), Data(bytes: bytes, count: count))
        }
    }
}
