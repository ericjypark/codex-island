import CryptoKit
import Foundation
import SQLite3

final class UsageLedger {
    enum Source: String, CaseIterable {
        case claude, codex, openCode, grok, antigravity
    }

    struct Snapshot {
        let events: [TokenEvent]
        let saveError: String?
        var historicalDays: [HistoricalUsageDay] = []
    }

    struct HistoricalBatch {
        let days: [HistoricalUsageDay]
        let capturedAt: Date
    }

    struct RecoveryCommit {
        let before: Snapshot
        let after: Snapshot
    }

    static let shared = UsageLedger()
    static let saveErrorMessage = "Usage history could not be saved. Check available disk space and try refreshing."
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/dev.codexisland.CodexIsland", isDirectory: true)
            .appendingPathComponent("usage-history.sqlite3")
    }

    let url: URL
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL = UsageLedger.defaultURL) {
        self.url = url
    }

    func retain(_ events: [TokenEvent], source: Source, now: Date = Date(), observedAt: Date? = nil,
                insertOnly: Bool = false) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let incoming = Self.records(events, now: now)
        let observedAt = observedAt ?? now
        var database: OpaquePointer?
        defer { if let database { sqlite3_close(database) } }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
                  let database else { throw StorageError.database }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            sqlite3_busy_timeout(database, 5000)
            try Self.prepareDatabase(database)
            try Self.execute(database, "BEGIN IMMEDIATE")
            do {
                let batch = Self.canonicalized(incoming, aliases: try Self.readAliases(source: source, database: database))
                let isCurrent = try Self.isCurrent(observedAt, source: source, database: database)
                try Self.upsert(batch.records, source: source, now: now, updateExisting: isCurrent && !insertOnly, database: database)
                try Self.saveAliases(batch.aliases, source: source, database: database)
                if isCurrent && !insertOnly { try Self.recordScan(observedAt, source: source, database: database) }
                try Self.execute(database, "COMMIT")
            } catch {
                try? Self.execute(database, "ROLLBACK")
                throw error
            }
            return Snapshot(events: try Self.read(source: source, database: database), saveError: nil,
                            historicalDays: try Self.readHistoricalDays(source: source, database: database))
        } catch {
            // A failed write must not hide either the previously saved history or this scan.
            let saved = database.flatMap { try? Self.read(source: source, database: $0) } ?? []
            var combined = Self.records(saved, now: now)
            let aliases = database.flatMap { try? Self.readAliases(source: source, database: $0) } ?? [:]
            let isCurrent = database.flatMap { try? Self.isCurrent(observedAt, source: source, database: $0) } ?? true
            combined.merge(Self.canonicalized(incoming, aliases: aliases).records) { saved, latest in isCurrent && !insertOnly ? latest : saved }
            let historical = database.flatMap { try? Self.readHistoricalDays(source: source, database: $0) } ?? []
            return Snapshot(events: Array(combined.values), saveError: Self.saveErrorMessage, historicalDays: historical)
        }
    }

    @discardableResult
    func copyDatabase(to destination: URL) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw StorageError.database }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var sourcePointer: OpaquePointer?, targetPointer: OpaquePointer?
        var isPortable = false
        defer {
            if let sourcePointer { sqlite3_close(sourcePointer) }
            if let targetPointer { sqlite3_close(targetPointer) }
            if isPortable {
                for suffix in ["-shm", "-wal"] {
                    try? FileManager.default.removeItem(atPath: destination.path + suffix)
                }
            }
        }
        guard sqlite3_open_v2(url.path, &sourcePointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let source = sourcePointer,
              sqlite3_open_v2(destination.path, &targetPointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let target = targetPointer else { throw StorageError.database }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        sqlite3_busy_timeout(source, 5000)
        sqlite3_busy_timeout(target, 5000)
        guard let backup = sqlite3_backup_init(target, "main", source, "main") else { throw StorageError.database }
        let copied = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard copied == SQLITE_DONE, finished == SQLITE_OK else { throw StorageError.database }
        // A portable backup must not need WAL sidecars during its first read-only open.
        let mode = try Self.statement(target, "PRAGMA journal_mode=DELETE")
        let modeStatus = sqlite3_step(mode)
        let modeName = sqlite3_column_text(mode, 0).map { String(cString: $0) }
        sqlite3_finalize(mode)
        guard modeStatus == SQLITE_ROW, modeName == "delete" else { throw StorageError.database }
        isPortable = true
        return true
    }

    func importHistoricalDays(_ days: [HistoricalUsageDay], capturedAt: Date, preserveLargerTotals: Bool = false) throws {
        try Self.validateHistoricalDays(days, capturedAt: capturedAt)
        try writeTransaction { database in
            try Self.upsertHistoricalDays(days, capturedAt: capturedAt, preserveLargerTotals: preserveLargerTotals, database: database)
            try Self.validateHistoricalIntervals(providers: Set(days.map(\.provider)), database: database)
        }
    }

    func recoverClaude(_ events: [TokenEvent], historicalBatches: [HistoricalBatch], now: Date) throws -> RecoveryCommit {
        guard events.allSatisfy({ $0.provider == .claude }),
              historicalBatches.flatMap(\.days).allSatisfy({ $0.provider == .claude }) else { throw StorageError.record }
        try Self.validateHistoricalDays(historicalBatches.flatMap(\.days), capturedAt: now)
        for batch in historicalBatches { try Self.validateHistoricalDays(batch.days, capturedAt: batch.capturedAt) }
        let incoming = Self.records(events, now: now)
        return try writeTransaction { database in
            let before = try Self.readClaudeHistory(database: database)
            let batch = Self.canonicalized(incoming, aliases: try Self.readAliases(source: .claude, database: database))
            try Self.upsert(batch.records, source: .claude, now: now, updateExisting: false, database: database)
            try Self.saveAliases(batch.aliases, source: .claude, database: database)
            for historical in historicalBatches.sorted(by: { $0.capturedAt < $1.capturedAt }) {
                try Self.upsertHistoricalDays(historical.days, capturedAt: historical.capturedAt,
                                             preserveLargerTotals: true, database: database)
            }
            try Self.validateHistoricalIntervals(providers: [.claude], database: database)
            let after = try Self.readClaudeHistory(database: database)
            return RecoveryCommit(before: before, after: after)
        }
    }

    private static func readClaudeHistory(database: OpaquePointer) throws -> Snapshot {
        let events = try read(source: .claude, database: database)
            + read(source: .openCode, database: database).filter { $0.provider == .claude }
        let days = try readHistoricalDays(source: .claude, database: database)
        var total = 0
        for count in events.flatMap({ [$0.inputTokens, $0.outputTokens, $0.cacheCreationTokens, $0.cacheReadTokens] })
            + days.map(\.tokensIncludingCache) {
            let result = total.addingReportingOverflow(count)
            guard count >= 0, !result.overflow, result.partialValue <= Int.max / 4 else { throw StorageError.record }
            total = result.partialValue
        }
        return Snapshot(events: events, saveError: nil, historicalDays: days)
    }

    func savedSnapshot(source: Source) throws -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot(events: [], saveError: nil) }
        var pointer: OpaquePointer?
        defer { if let pointer { sqlite3_close(pointer) } }
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database = pointer else { throw StorageError.database }
        sqlite3_busy_timeout(database, 5000)
        let version = try Self.statement(database, "PRAGMA user_version")
        defer { sqlite3_finalize(version) }
        let status = sqlite3_step(version)
        guard status == SQLITE_ROW else { throw StorageError.database }
        guard sqlite3_column_int(version, 0) == 1 else { throw StorageError.schema }
        return Snapshot(events: try Self.read(source: source, database: database), saveError: nil,
                        historicalDays: try Self.readHistoricalDays(source: source, database: database))
    }

    private static func validateHistoricalDays(_ days: [HistoricalUsageDay], capturedAt: Date) throws {
        let keys = days.map { "\($0.provider.rawValue):\($0.intervalStart.timeIntervalSince1970.bitPattern)" }
        guard days.allSatisfy(\.isValid), Set(keys).count == keys.count,
              capturedAt.timeIntervalSince1970.isFinite, capturedAt.timeIntervalSince1970 > 0 else { throw StorageError.record }
    }

    private func writeTransaction<Result>(_ operation: (OpaquePointer) throws -> Result) throws -> Result {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database = pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw StorageError.database
        }
        defer { sqlite3_close(database) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        sqlite3_busy_timeout(database, 5000)
        try Self.prepareDatabase(database)
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let result = try operation(database)
            try Self.execute(database, "COMMIT")
            return result
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    private static func upsertHistoricalDays(_ days: [HistoricalUsageDay], capturedAt: Date,
                                             preserveLargerTotals: Bool, database: OpaquePointer) throws {
        let recoveryCondition = preserveLargerTotals
            ? " AND excluded.tokens >= tokens AND excluded.billable_tokens >= billable_tokens" : ""
        let statement = try statement(database, """
            INSERT INTO historical_daily_usage VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(provider, interval_start) DO UPDATE SET
                interval_end=excluded.interval_end, source_date=excluded.source_date,
                utc_offset=excluded.utc_offset, tokens=excluded.tokens, billable_tokens=excluded.billable_tokens,
                evidence_id=excluded.evidence_id, captured_at=excluded.captured_at
            WHERE excluded.captured_at >= captured_at\(recoveryCondition)
            """)
        defer { sqlite3_finalize(statement) }
        for day in days {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(day.provider.rawValue, at: 1, to: statement)
            guard sqlite3_bind_double(statement, 2, day.intervalStart.timeIntervalSince1970) == SQLITE_OK,
                  sqlite3_bind_double(statement, 3, day.intervalEnd.timeIntervalSince1970) == SQLITE_OK else { throw StorageError.database }
            try bind(day.sourceLocalDate, at: 4, to: statement)
            guard sqlite3_bind_int(statement, 5, Int32(day.sourceUTCOffsetSeconds)) == SQLITE_OK,
                  sqlite3_bind_int64(statement, 6, Int64(day.tokensIncludingCache)) == SQLITE_OK,
                  sqlite3_bind_int64(statement, 7, Int64(day.inputPlusOutputTokens)) == SQLITE_OK else { throw StorageError.database }
            try bind(digest(day.sourceIdentity, provider: day.provider), at: 8, to: statement)
            guard sqlite3_bind_double(statement, 9, capturedAt.timeIntervalSince1970) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE else { throw StorageError.database }
        }
    }

    private static func validateHistoricalIntervals(providers: Set<TokenEvent.Provider>, database: OpaquePointer) throws {
        for provider in providers {
            guard let source = Source(rawValue: provider.rawValue) else { throw StorageError.record }
            let saved = try readHistoricalDays(source: source, database: database)
            for pair in zip(saved, saved.dropFirst()) where pair.0.intervalEnd > pair.1.intervalStart { throw StorageError.record }
        }
    }

    private static func records(_ events: [TokenEvent], now: Date) -> [String: TokenEvent] {
        var result: [String: TokenEvent] = [:]
        var occurrences: [String: Int] = [:]
        for event in events {
            let counts = [event.inputTokens, event.outputTokens, event.cacheCreationTokens, event.cacheReadTokens]
            guard event.timestamp.timeIntervalSince1970.isFinite,
                  event.timestamp.timeIntervalSince1970 > 0, event.timestamp <= now,
                  counts.allSatisfy({ $0 >= 0 && $0 <= Int.max / 4 }), counts.contains(where: { $0 > 0 }) else { continue }
            let key: String
            if let id = event.recordID, id.hasPrefix("ledger:") {
                key = String(id.dropFirst(7))
            } else {
                let identity: String
                if let id = event.recordID, !id.isEmpty {
                    identity = id
                } else {
                    let base = "\(event.provider.rawValue):\(event.timestamp.timeIntervalSince1970.bitPattern):\(event.model)"
                    let occurrence = occurrences[base, default: 0]
                    occurrences[base] = occurrence + 1
                    identity = "fallback:\(base):\(occurrence)"
                }
                key = digest(identity, provider: event.provider)
            }
            result[key] = event
        }
        return result
    }

    private static func digest(_ identity: String, provider: TokenEvent.Provider) -> String {
        let input = [provider.rawValue, identity].map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalized(_ records: [String: TokenEvent], aliases: [String: String])
        -> (records: [String: TokenEvent], aliases: [String: String]) {
        var known = aliases
        var added: [String: String] = [:]
        var result: [String: TokenEvent] = [:]
        for (key, event) in records {
            let keys = [key] + event.recordAliases.map { digest($0, provider: event.provider) }
            let canonical = keys.compactMap { known[$0] }.first ?? key
            result[canonical] = event
            for alias in keys where known[alias] == nil {
                known[alias] = canonical
                added[alias] = canonical
            }
        }
        return (result, added)
    }

    private enum StorageError: Error { case database, schema, record }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StorageError.database }
    }

    private static func statement(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.database
        }
        return statement
    }

    private static func prepareDatabase(_ database: OpaquePointer) throws {
        let versionStatement = try statement(database, "PRAGMA user_version")
        let status = sqlite3_step(versionStatement)
        let version = sqlite3_column_int(versionStatement, 0)
        sqlite3_finalize(versionStatement)
        guard status == SQLITE_ROW else { throw StorageError.database }
        guard version == 0 || version == 1 else { throw StorageError.schema }
        try execute(database, "PRAGMA journal_mode=WAL")
        try execute(database, "PRAGMA synchronous=FULL")
        guard version == 0 else { return }
        try execute(database, """
            CREATE TABLE IF NOT EXISTS usage_events (
                source TEXT NOT NULL,
                record_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                timestamp REAL NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL CHECK (input_tokens >= 0),
                output_tokens INTEGER NOT NULL CHECK (output_tokens >= 0),
                cache_creation_tokens INTEGER NOT NULL CHECK (cache_creation_tokens >= 0),
                cache_read_tokens INTEGER NOT NULL CHECK (cache_read_tokens >= 0),
                captured_at REAL NOT NULL,
                PRIMARY KEY (source, record_id)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS event_aliases (
                source TEXT NOT NULL,
                alias_id TEXT NOT NULL,
                record_id TEXT NOT NULL,
                PRIMARY KEY (source, alias_id)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS source_scans (
                source TEXT PRIMARY KEY,
                observed_at REAL NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS historical_daily_usage (
                provider TEXT NOT NULL,
                interval_start REAL NOT NULL,
                interval_end REAL NOT NULL,
                source_date TEXT NOT NULL,
                utc_offset INTEGER NOT NULL,
                tokens INTEGER NOT NULL CHECK (tokens > 0),
                billable_tokens INTEGER NOT NULL CHECK (billable_tokens >= 0 AND billable_tokens <= tokens),
                evidence_id TEXT NOT NULL,
                captured_at REAL NOT NULL,
                PRIMARY KEY (provider, interval_start)
            ) WITHOUT ROWID;
            PRAGMA user_version=1;
            """)
    }

    private static func readHistoricalDays(source: Source, database: OpaquePointer) throws -> [HistoricalUsageDay] {
        guard let provider = TokenEvent.Provider(rawValue: source.rawValue) else { return [] }
        let statement = try statement(database, """
            SELECT interval_start, interval_end, source_date, utc_offset, tokens, billable_tokens, evidence_id
            FROM historical_daily_usage WHERE provider=? ORDER BY interval_start
            """)
        defer { sqlite3_finalize(statement) }
        try bind(provider.rawValue, at: 1, to: statement)
        var days: [HistoricalUsageDay] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return days }
            guard status == SQLITE_ROW, let date = sqlite3_column_text(statement, 2),
                  let identity = sqlite3_column_text(statement, 6) else { throw StorageError.database }
            let day = HistoricalUsageDay(provider: provider, sourceIdentity: String(cString: identity),
                                         intervalStart: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                                         intervalEnd: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                                         sourceLocalDate: String(cString: date), sourceUTCOffsetSeconds: Int(sqlite3_column_int(statement, 3)),
                                         tokensIncludingCache: Int(sqlite3_column_int64(statement, 4)),
                                         inputPlusOutputTokens: Int(sqlite3_column_int64(statement, 5)))
            guard day.isValid else { throw StorageError.record }
            days.append(day)
        }
    }

    private static func isCurrent(_ date: Date, source: Source, database: OpaquePointer) throws -> Bool {
        let statement = try statement(database, "SELECT observed_at FROM source_scans WHERE source=?")
        defer { sqlite3_finalize(statement) }
        try bind(source.rawValue, at: 1, to: statement)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return true }
        guard status == SQLITE_ROW else { throw StorageError.database }
        return date.timeIntervalSince1970 >= sqlite3_column_double(statement, 0)
    }

    private static func recordScan(_ date: Date, source: Source, database: OpaquePointer) throws {
        let statement = try statement(database, """
            INSERT INTO source_scans VALUES (?, ?)
            ON CONFLICT(source) DO UPDATE SET observed_at=excluded.observed_at
            """)
        defer { sqlite3_finalize(statement) }
        try bind(source.rawValue, at: 1, to: statement)
        guard sqlite3_bind_double(statement, 2, date.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw StorageError.database }
    }

    private static func readAliases(source: Source, database: OpaquePointer) throws -> [String: String] {
        let statement = try statement(database, "SELECT alias_id, record_id FROM event_aliases WHERE source=?")
        defer { sqlite3_finalize(statement) }
        try bind(source.rawValue, at: 1, to: statement)
        var aliases: [String: String] = [:]
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return aliases }
            guard status == SQLITE_ROW, let alias = sqlite3_column_text(statement, 0),
                  let key = sqlite3_column_text(statement, 1) else { throw StorageError.database }
            aliases[String(cString: alias)] = String(cString: key)
        }
    }

    private static func saveAliases(_ aliases: [String: String], source: Source, database: OpaquePointer) throws {
        let statement = try statement(database, "INSERT OR IGNORE INTO event_aliases VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        for (alias, key) in aliases {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(source.rawValue, at: 1, to: statement)
            try bind(alias, at: 2, to: statement)
            try bind(key, at: 3, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw StorageError.database }
        }
    }

    private static func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else { throw StorageError.database }
    }

    private static func upsert(_ records: [String: TokenEvent], source: Source, now: Date,
                               updateExisting: Bool, database: OpaquePointer) throws {
        let onConflict = updateExisting ? """
            DO UPDATE SET
                provider=excluded.provider, timestamp=excluded.timestamp, model=excluded.model,
                input_tokens=excluded.input_tokens, output_tokens=excluded.output_tokens,
                cache_creation_tokens=excluded.cache_creation_tokens, cache_read_tokens=excluded.cache_read_tokens
            WHERE provider != excluded.provider OR timestamp != excluded.timestamp OR model != excluded.model
                OR input_tokens != excluded.input_tokens OR output_tokens != excluded.output_tokens
                OR cache_creation_tokens != excluded.cache_creation_tokens OR cache_read_tokens != excluded.cache_read_tokens
            """ : "DO NOTHING"
        let statement = try statement(database,
                                      "INSERT INTO usage_events VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(source, record_id) \(onConflict)")
        defer { sqlite3_finalize(statement) }
        for (key, event) in records {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(source.rawValue, at: 1, to: statement)
            try bind(key, at: 2, to: statement)
            try bind(event.provider.rawValue, at: 3, to: statement)
            guard sqlite3_bind_double(statement, 4, event.timestamp.timeIntervalSince1970) == SQLITE_OK else { throw StorageError.database }
            try bind(event.model, at: 5, to: statement)
            for (offset, count) in [event.inputTokens, event.outputTokens, event.cacheCreationTokens, event.cacheReadTokens].enumerated() {
                guard sqlite3_bind_int64(statement, Int32(offset + 6), Int64(count)) == SQLITE_OK else { throw StorageError.database }
            }
            guard sqlite3_bind_double(statement, 10, now.timeIntervalSince1970) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_DONE else { throw StorageError.database }
        }
    }

    private static func read(source: Source, database: OpaquePointer) throws -> [TokenEvent] {
        let statement = try statement(database, """
            SELECT record_id, provider, timestamp, model, input_tokens, output_tokens,
                   cache_creation_tokens, cache_read_tokens
            FROM usage_events WHERE source=? ORDER BY timestamp, record_id
            """)
        defer { sqlite3_finalize(statement) }
        try bind(source.rawValue, at: 1, to: statement)
        var events: [TokenEvent] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return events }
            guard status == SQLITE_ROW,
                  let key = sqlite3_column_text(statement, 0),
                  let providerText = sqlite3_column_text(statement, 1),
                  let provider = TokenEvent.Provider(rawValue: String(cString: providerText)),
                  let model = sqlite3_column_text(statement, 3) else { throw StorageError.record }
            events.append(TokenEvent(provider: provider,
                                     timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                                     model: String(cString: model),
                                     inputTokens: Int(sqlite3_column_int64(statement, 4)),
                                     outputTokens: Int(sqlite3_column_int64(statement, 5)),
                                     cacheCreationTokens: Int(sqlite3_column_int64(statement, 6)),
                                     cacheReadTokens: Int(sqlite3_column_int64(statement, 7)),
                                     recordID: "ledger:\(String(cString: key))"))
        }
    }
}
