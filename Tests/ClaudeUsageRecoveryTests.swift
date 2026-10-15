import Foundation
import SQLite3

enum L10n {
    static let locale = Locale(identifier: "en_US")
    static func tr(_ text: String, _ args: CVarArg...) -> String { String(format: text, arguments: args) }
}

@main
struct ClaudeUsageRecoveryTests {
    static var checks = 0
    static let now = Date(timeIntervalSince1970: 1_789_070_400)

    struct Cache: Encodable {
        let claudeDailyTokens: [DailyTokenBucket]
        var lastUpdated = now
    }

    static func expect(_ value: Bool, _ label: String) {
        guard value else { print("FAIL \(label)"); exit(1) }
        checks += 1
        print("PASS \(label)")
    }

    static func date(_ value: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw ClaudeUsageRecovery.RecoveryError.message("Invalid fixture date")
        }
        return date
    }

    static func log(id: String?, timestamp: String = "2026-01-09T03:00:00Z", tokens: Int = 100) throws -> Data {
        var message: [String: Any] = ["model": "claude-sonnet-4-6", "usage": ["input_tokens": tokens]]
        if let id { message["id"] = id }
        var value: [String: Any] = ["type": "assistant", "timestamp": timestamp, "message": message]
        if id != nil { value["requestId"] = "request" }
        var data = try JSONSerialization.data(withJSONObject: value)
        data.append(10)
        return data
    }

    static func preferences(_ url: URL, snapshots: [String: [DailyTokenBucket]]) throws {
        let data = try snapshots.mapValues { try JSONEncoder().encode(Cache(claudeDailyTokens: $0)) }
        try PropertyListSerialization.data(fromPropertyList: data, format: .binary, options: 0).write(to: url)
    }

    static func run(_ arguments: [String], ledger: UsageLedger, roots: [URL] = [], preferences: [URL] = []) -> (Int32, String) {
        var lines: [String] = []
        let status = ClaudeUsageRecovery.run(arguments: arguments, ledger: ledger, defaultRoots: roots,
                                            defaultPreferences: preferences, output: { lines.append($0) })
        return (status, lines.joined(separator: "\n"))
    }

    static func tokens(_ snapshot: UsageLedger.Snapshot) -> Int {
        let detailed = snapshot.events.reduce(0) { $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreationTokens + $1.cacheReadTokens }
        return detailed + HistoricalUsageDay.supplements(snapshot.historicalDays, events: snapshot.events, calendar: .current)
            .reduce(0) { $0 + $1.tokens }
    }

    static func execute(_ url: URL, sql: String) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open(url.path, &pointer) == SQLITE_OK, let database = pointer else {
            throw ClaudeUsageRecovery.RecoveryError.message("Could not open fixture archive")
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw ClaudeUsageRecovery.RecoveryError.message("Could not prepare fixture archive")
        }
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-recovery-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects")
        let backup = root.appendingPathComponent("backup with spaces")
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let normalFile = projects.appendingPathComponent("session.jsonl")
        let backupFile = backup.appendingPathComponent("session.jsonl")
        var original = try log(id: "one")
        original.append(try log(id: nil, tokens: 999_999))
        try original.write(to: normalFile)
        var copied = try log(id: "one")
        copied.append(try log(id: "older", timestamp: "2026-01-10T03:00:00Z", tokens: 300))
        try copied.write(to: backupFile)
        let plist = root.appendingPathComponent("old preferences.plist")
        let day = DailyTokenBucket(dayStart: try date("2026-01-08T15:00:00Z"), tokens: 1000, billableTokens: 1000)
        try preferences(plist, snapshots: ["MacIsland.costCache.v5": [day], "MacIsland.costCache.v6": [day]])
        let plistBefore = try Data(contentsOf: plist)
        let archive = root.appendingPathComponent("archive/history.sqlite3")
        let ledger = UsageLedger(url: archive)
        let arguments = ["--projects", backup.path, "--time-zone", "Asia/Seoul"]

        expect(run(["--help"], ledger: ledger).0 == 0, "help exits without starting the app")
        expect(!FileManager.default.fileExists(atPath: archive.path), "help does not create an archive")
        expect(run(["--aply"], ledger: ledger).0 == 1, "unknown flag fails")
        expect(run(["--projects"], ledger: ledger).0 == 1, "missing folder value fails")
        expect(run(["--projects", root.appendingPathComponent("missing").path], ledger: ledger).0 == 1, "missing backup fails")
        expect(run(["--time-zone", "Not/AZone"], ledger: ledger).0 == 1, "unknown timezone fails")
        let preview = run(arguments, ledger: ledger, roots: [projects], preferences: [plist])
        expect(preview.0 == 0 && preview.1.contains("Additional tokens:              1,300"), "preview combines detailed records and only aggregate remainder")
        expect(preview.1.contains("Found 2 distinct messages") && preview.1.contains("1 saved daily totals"), "copied logs and repeated cache versions are deduplicated")
        expect(!FileManager.default.fileExists(atPath: archive.path), "preview leaves the real archive absent")
        let noZone = run([], ledger: ledger, roots: [projects], preferences: [plist])
        expect(noZone.1.contains("--time-zone") && noZone.1.contains("Additional tokens:              100"), "unknown original timezone is never guessed")
        let wrongZone = run(["--time-zone", "America/Chicago"], ledger: ledger, preferences: [plist])
        expect(wrongZone.0 == 0 && wrongZone.1.contains("daily boundaries do not match") && wrongZone.1.contains("0 saved daily totals"), "wrong timezone cannot shift old daily totals")

        let applied = run(arguments + ["--apply"], ledger: ledger, roots: [projects], preferences: [plist])
        expect(applied.0 == 0 && applied.1.contains("Saved. Claude tokens now preserved: 1,300"), "apply saves verified records")
        let first = ledger.retain([], source: .claude, now: now, insertOnly: true)
        expect(first.events.count == 2 && first.historicalDays.count == 1 && tokens(first) == 1300, "imported archive matches preview")
        expect(first.historicalDays.first?.sourceLocalDate == "2026-01-09", "Korean source date is preserved")
        expect(first.historicalDays.first?.sourceUTCOffsetSeconds == 9 * 3600, "original UTC interval is preserved")
        let permission = try FileManager.default.attributesOfItem(atPath: archive.path)[.posixPermissions] as? NSNumber
        expect(permission?.intValue == 0o600, "usage archive stays private")
        let repeated = run(arguments + ["--apply"], ledger: ledger, roots: [projects], preferences: [plist])
        expect(repeated.0 == 0 && repeated.1.contains("No additional verified tokens"), "repeating recovery is a no-op")
        expect(!FileManager.default.fileExists(atPath: archive.deletingLastPathComponent().appendingPathComponent("Recovery Backups").path), "no-op recovery does not create unnecessary backups")
        expect(try Data(contentsOf: normalFile) == original && Data(contentsOf: backupFile) == copied && Data(contentsOf: plist) == plistBefore, "source logs and preferences are unchanged")

        let extra = projects.appendingPathComponent("new.jsonl")
        try log(id: "extra", timestamp: "2026-02-01T03:00:00Z", tokens: 50).write(to: extra)
        let more = run(arguments + ["--apply"], ledger: ledger, roots: [projects], preferences: [plist])
        expect(more.0 == 0 && more.1.contains("Archive backup:") && more.1.contains("preserved: 1,350"), "new recovery backs up an existing archive before adding records")
        let backups = try FileManager.default.contentsOfDirectory(at: archive.deletingLastPathComponent().appendingPathComponent("Recovery Backups"), includingPropertiesForKeys: nil)
        expect(backups.count == 1, "one consistent archive backup is retained")
        let prior = try UsageLedger(url: backups[0]).savedSnapshot(source: .claude)
        expect(tokens(prior) == 1300 && prior.events.count == 2, "portable backup opens read-only with pre-import WAL records and daily aggregates")
        try FileManager.default.removeItem(at: projects)
        try FileManager.default.removeItem(at: backup)
        expect(tokens(ledger.retain([], source: .claude, now: now, insertOnly: true)) == 1350, "recovered counts survive deleting all provider fixtures")

        let conflictPlist = root.appendingPathComponent("conflict.plist")
        let conflicting = DailyTokenBucket(dayStart: day.dayStart, tokens: 900, billableTokens: 900)
        let differentBreakdown = DailyTokenBucket(dayStart: day.dayStart, tokens: 1100, billableTokens: 800)
        try preferences(conflictPlist, snapshots: ["MacIsland.costCache.v5": [conflicting], "MacIsland.costCache.v6": [differentBreakdown]])
        let conflict = run(["--time-zone", "Asia/Seoul"], ledger: ledger, preferences: [conflictPlist])
        expect(conflict.0 == 0 && conflict.1.contains("conflicting saved counters") && conflict.1.contains("0 saved daily totals"), "noncomparable daily counters are not combined")

        let daylight = DailyTokenBucket(dayStart: try date("2026-03-08T06:00:00Z"), tokens: 20, billableTokens: 20)
        try preferences(conflictPlist, snapshots: ["MacIsland.costCache.v6": [daylight]])
        let daylightCandidates = try ClaudeUsageRecovery.dailyCandidates(preferences: [conflictPlist], timeZone: TimeZone(identifier: "America/Chicago"), now: now, output: { _ in })
        expect(daylightCandidates.count == 1 && daylightCandidates[0].day.intervalEnd.timeIntervalSince(daylightCandidates[0].day.intervalStart) == 23 * 3600, "daylight saving recovery uses actual 23-hour interval")

        var alreadyRecovered = day
        alreadyRecovered.recoveredTokens = 1000
        try preferences(conflictPlist, snapshots: ["MacIsland.costCache.v7": [alreadyRecovered]])
        expect(run(["--time-zone", "Asia/Seoul"], ledger: ledger, preferences: [conflictPlist]).1.contains("already contains recovered aggregates"), "recovered display buckets are not reinterpreted as raw history")

        try preferences(conflictPlist, snapshots: ["MacIsland.costCache.v6": [day, day]])
        expect(run(["--apply", "--time-zone", "Asia/Seoul"], ledger: ledger, preferences: [conflictPlist]).0 == 1, "malformed duplicate daily records stop before import")
        expect(tokens(ledger.retain([], source: .claude, now: now, insertOnly: true)) == 1350, "invalid recovery preserves existing history")

        let broken = root.appendingPathComponent("broken.sqlite3")
        let brokenData = Data("not a database".utf8)
        try brokenData.write(to: broken)
        expect(run(["--apply"], ledger: UsageLedger(url: broken)).0 == 1, "unreadable archive stops recovery")
        expect(try Data(contentsOf: broken) == brokenData, "unreadable archive is never replaced")

        let richer = TokenEvent(provider: .claude, timestamp: now, model: "claude-sonnet-4-6", inputTokens: 100,
                               outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, recordID: "existing")
        _ = ledger.retain([richer], source: .claude, now: now)
        let poorer = TokenEvent(provider: .claude, timestamp: now, model: richer.model, inputTokens: 1,
                               outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, recordID: "existing")
        let preserved = ledger.retain([poorer], source: .claude, now: now.addingTimeInterval(1), insertOnly: true)
        expect(tokens(preserved) == 1450, "an older backup cannot downgrade an existing message")
        let lower = HistoricalUsageDay(provider: .claude, sourceIdentity: "lower", intervalStart: day.dayStart,
            intervalEnd: day.dayStart.addingTimeInterval(86400), sourceLocalDate: "2026-01-09", sourceUTCOffsetSeconds: 9 * 3600,
            tokensIncludingCache: 800, inputPlusOutputTokens: 800)
        try ledger.importHistoricalDays([lower], capturedAt: now.addingTimeInterval(1), preserveLargerTotals: true)
        expect(tokens(ledger.retain([], source: .claude, now: now, insertOnly: true)) == 1450, "recovery cannot reduce already preserved daily totals")

        let interrupted = UsageLedger(url: root.appendingPathComponent("interrupted/archive.sqlite3"))
        _ = interrupted.retain([richer], source: .claude, now: now)
        let recoveryRoot = root.appendingPathComponent("failure-projects")
        try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
        try log(id: "not-partially-saved", tokens: 100).write(to: recoveryRoot.appendingPathComponent("new.jsonl"))
        try preferences(conflictPlist, snapshots: ["MacIsland.costCache.v6": [day]])
        var failureInstalled = false
        let stopped = ClaudeUsageRecovery.run(arguments: ["--apply", "--time-zone", "Asia/Seoul"], ledger: interrupted,
            defaultRoots: [recoveryRoot], defaultPreferences: [conflictPlist], output: { line in
                if line.hasPrefix("Archive backup:") {
                    do {
                        try execute(interrupted.url, sql: "CREATE TRIGGER reject_recovery BEFORE INSERT ON historical_daily_usage BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END;")
                        failureInstalled = true
                    } catch { exit(1) }
                }
            })
        expect(failureInstalled && stopped == 1, "write failure after preview stops the import")
        let untouched = interrupted.retain([], source: .claude, now: now, insertOnly: true)
        expect(untouched.events.count == 1 && untouched.historicalDays.isEmpty && tokens(untouched) == 100,
               "a failure while saving daily totals rolls back the entire recovery")

        let frozenLedger = UsageLedger(url: root.appendingPathComponent("frozen/archive.sqlite3"))
        let frozenFile = recoveryRoot.appendingPathComponent("new.jsonl")
        try log(id: "reviewed", tokens: 100).write(to: frozenFile)
        let frozen = try ClaudeUsageRecovery.prepare(options: .init(), ledger: frozenLedger,
                                                     defaultRoots: [recoveryRoot], defaultPreferences: [])
        var changedSource = try log(id: "reviewed", tokens: 999_999)
        changedSource.append(try log(id: "not-reviewed", tokens: 500))
        try changedSource.write(to: frozenFile)
        let frozenResult = try ClaudeUsageRecovery.apply(frozen, ledger: frozenLedger)
        expect(frozenResult.didSave && frozenResult.tokens == 100, "import saves the reviewed counters even if source files change")
        expect(try frozenLedger.savedSnapshot(source: .claude).events.count == 1, "records appearing after preview are not silently imported")
        try FileManager.default.removeItem(at: frozenFile)
        expect(try !ClaudeUsageRecovery.apply(frozen, ledger: frozenLedger).didSave, "replaying a reviewed plan is a no-op even after its source disappears")

        try log(id: "already-captured", tokens: 100).write(to: frozenFile)
        let concurrent = UsageLedger(url: root.appendingPathComponent("concurrent/archive.sqlite3"))
        let concurrentPlan = try ClaudeUsageRecovery.prepare(options: .init(), ledger: concurrent,
                                                             defaultRoots: [recoveryRoot], defaultPreferences: [])
        _ = concurrent.retain(ClaudeLogReader.scan(lookbackDays: nil, roots: [recoveryRoot]), source: .claude, now: now)
        let concurrentResult = try ClaudeUsageRecovery.apply(concurrentPlan, ledger: concurrent)
        expect(!concurrentResult.didSave && concurrentResult.tokens == 100 && concurrentResult.backupURL == nil,
               "usage captured by the app after preview is rechecked without duplicates or needless backups")

        let arriving = UsageLedger(url: root.appendingPathComponent("arriving/archive.sqlite3"))
        _ = arriving.retain([richer], source: .claude, now: now)
        try log(id: "arriving-recovery", tokens: 200).write(to: frozenFile)
        let arrivingPlan = try ClaudeUsageRecovery.prepare(options: .init(), ledger: arriving,
                                                           defaultRoots: [recoveryRoot], defaultPreferences: [])
        let normalCapture = TokenEvent(provider: .claude, timestamp: now, model: richer.model, inputTokens: 900,
                                       outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0, recordID: "normal-app")
        let arrivingResult = try ClaudeUsageRecovery.apply(arrivingPlan, ledger: arriving, backupCreated: { _ in
            _ = arriving.retain([normalCapture], source: .claude, now: now)
        })
        expect(arrivingResult.tokens == 1200 && arrivingResult.additionalTokens == 200,
               "normal app captures during import are not reported as recovered tokens")

        let invalid = UsageLedger(url: root.appendingPathComponent("invalid/archive.sqlite3"))
        var excessive = try log(id: "large-one", tokens: Int.max / 4)
        excessive.append(try log(id: "large-two", tokens: Int.max / 4))
        try excessive.write(to: frozenFile)
        let overflow = run(["--apply"], ledger: invalid, roots: [recoveryRoot])
        expect(overflow.0 == 1 && overflow.1.contains("supported range"), "excessive counters fail safely instead of overflowing")
        expect(!FileManager.default.fileExists(atPath: invalid.url.path), "out-of-range recovery cannot create a real archive")
        var invalidCounts = try log(id: "negative", tokens: -100)
        invalidCounts.append(try log(id: "future", timestamp: "2099-01-01T00:00:00Z", tokens: 500))
        try invalidCounts.write(to: frozenFile)
        let invalidPreview = run([], ledger: invalid, roots: [recoveryRoot])
        expect(invalidPreview.0 == 0 && invalidPreview.1.contains("Skipped 2 records") && invalidPreview.1.contains("Found 0 distinct messages"),
               "invalid and future records are disclosed and excluded from the preview")

        let futureArchive = UsageLedger(url: root.appendingPathComponent("future-schema/archive.sqlite3"))
        _ = futureArchive.retain([richer], source: .claude, now: now)
        try execute(futureArchive.url, sql: "PRAGMA user_version=99;")
        let originalFutureArchive = try Data(contentsOf: futureArchive.url)
        expect(run(["--apply"], ledger: futureArchive).0 == 1, "an unsupported archive schema stops recovery")
        expect(try Data(contentsOf: futureArchive.url) == originalFutureArchive, "unsupported archives are preserved byte for byte")

        let portableCopy = root.appendingPathComponent("portable.sqlite3")
        try FileManager.default.copyItem(at: backups[0], to: portableCopy)
        expect(try tokens(UsageLedger(url: portableCopy).savedSnapshot(source: .claude)) == 1300,
               "copying only the backup database is sufficient for a read-only restore")
        print("PASS all \(checks) Claude recovery checks")
    }
}
