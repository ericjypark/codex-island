import Foundation
import SQLite3

enum L10n {
    static let locale = Locale(identifier: "en_US")
    static func tr(_ text: String, _ args: CVarArg...) -> String { String(format: text, arguments: args) }
}

@main
struct UsageLedgerTests {
    static let now = Date(timeIntervalSince1970: 1_789_070_400)
    static var checks = 0

    static func expect(_ condition: Bool, _ label: String) {
        guard condition else { print("FAIL \(label)"); exit(1) }
        checks += 1
        print("PASS \(label)")
    }

    static func event(_ id: String, input: Int = 100, output: Int = 20,
                      provider: TokenEvent.Provider = .claude, date: Date = now) -> TokenEvent {
        TokenEvent(provider: provider, timestamp: date, model: "claude-sonnet-4-6",
                   inputTokens: input, outputTokens: output, cacheCreationTokens: 30,
                   cacheReadTokens: 400, recordID: id)
    }

    static func total(_ events: [TokenEvent]) -> Int {
        events.reduce(0) { $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreationTokens + $1.cacheReadTokens }
    }

    static func execute(_ url: URL, sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw TestError.database }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw TestError.database }
    }

    static func count(_ url: URL) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw TestError.database }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM usage_events", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw TestError.database }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw TestError.database }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private enum TestError: Error { case database }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usage-ledger-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("archive/usage.sqlite3")
        let ledger = UsageLedger(url: url)
        let first = ledger.retain([event("one")], source: .claude, now: now)
        expect(first.saveError == nil && total(first.events) == 550, "capture preserves every token category")
        expect(ledger.retain([event("one")], source: .claude, now: now).events.count == 1, "repeated scans do not add usage")
        expect(ledger.retain(first.events, source: .claude, now: now).events.count == 1, "saved rows can be read and retained idempotently")
        let reopened = UsageLedger(url: url).retain([], source: .claude, now: now)
        expect(reopened.saveError == nil && total(reopened.events) == 550, "new instance reads saved counts without any provider records")
        let later = now.addingTimeInterval(500 * 86400)
        expect(total(ledger.retain([], source: .claude, now: later).events) == 550, "history survives year boundaries without expiry")
        let added = ledger.retain([event("two", input: 200, date: later)], source: .claude, now: later)
        expect(added.events.count == 2 && total(added.events) == 1200, "new usage adds to history after old source logs disappear")
        let corrected = ledger.retain([event("one", input: 50)], source: .claude, now: later)
        expect(corrected.events.count == 2 && total(corrected.events) == 1150, "corrected counts replace the same call instead of adding a second call")
        let summary = CostSummary.summarize(events: corrected.events, now: later, includeAllHistory: true)
        expect(summary.dailyTokens.reduce(0) { $0 + $1.tokens } == 1150, "saved records feed the real all-time card aggregation")
        expect(abs(summary.dailyTokens.compactMap(\.dollars).reduce(0, +)
                   - corrected.events.reduce(0) { $0 + Pricing.cost(for: $1) }) < 0.000001,
               "API estimates remain derived from separate raw token categories")
        expect(ledger.retain([event("one")], source: .openCode, now: now).events.count == 1,
               "independent clients with matching IDs stay separate")
        expect(ledger.retain([event("one", provider: .codex)], source: .openCode, now: now).events.count == 2,
               "provider identity prevents cross-provider collisions")
        let fallback = TokenEvent(provider: .claude, timestamp: now, model: "unknown",
                                  inputTokens: 1, outputTokens: 1, cacheCreationTokens: 0, cacheReadTokens: 0)
        let fallbackURL = root.appendingPathComponent("fallback.sqlite3")
        let fallbackLedger = UsageLedger(url: fallbackURL)
        expect(fallbackLedger.retain([fallback, fallback], source: .claude, now: now).events.count == 2,
               "distinct identical records without IDs are not collapsed")
        expect(fallbackLedger.retain([fallback, fallback], source: .claude, now: now).events.count == 2,
               "fallback identities stay stable on repeated scans")

        let forkLedger = UsageLedger(url: root.appendingPathComponent("fork.sqlite3"))
        var original = event("original")
        original.recordAliases = ["same-model-call"]
        var fork = event("fork")
        fork.recordAliases = original.recordAliases
        _ = forkLedger.retain([original], source: .openCode, now: now)
        expect(forkLedger.retain([fork], source: .openCode, now: now).events.count == 1,
               "a surviving fork cannot recount a deleted original message")
        var updatedFork = event("fork", input: 200)
        updatedFork.recordAliases = ["updated-model-call"]
        let forkResult = forkLedger.retain([updatedFork], source: .openCode, now: now)
        expect(forkResult.events.count == 1 && total(forkResult.events) == 650,
               "aliases retain call identity when a fork's usage is corrected")

        let raceLedger = UsageLedger(url: root.appendingPathComponent("scan-order.sqlite3"))
        _ = raceLedger.retain([event("call", input: 200)], source: .claude, now: later, observedAt: later)
        let stale = raceLedger.retain([event("call", input: 100), event("older-log")], source: .claude,
                                     now: later, observedAt: now)
        expect(stale.events.count == 2 && total(stale.events) == 1200,
               "a slow earlier scan adds missing history without overwriting newer counts")
        let correctedLater = raceLedger.retain([event("call", input: 50)], source: .claude,
                                               now: later, observedAt: later.addingTimeInterval(1))
        expect(total(correctedLater.events) == 1050, "a newer correction can still reduce a previously recorded count")

        let invalid = ledger.retain([event("negative", input: -1), event("future", date: later.addingTimeInterval(1)),
                                     event("missing-date", date: .distantPast)], source: .grok, now: later)
        expect(invalid.events.isEmpty, "invalid and future records do not create fabricated history")
        try execute(url, sql: "CREATE TRIGGER reject_fixture BEFORE INSERT ON usage_events WHEN NEW.input_tokens=9999 BEGIN SELECT RAISE(ABORT, 'fixture'); END;")
        let beforeFailure = try count(url)
        let failed = ledger.retain([event("three"), event("rejected", input: 9999)], source: .claude, now: later)
        expect(failed.saveError != nil, "storage failures are reported")
        expect(try count(url) == beforeFailure, "a failed batch rolls back all writes")
        expect(failed.events.count == 4, "failed writes still show saved history and current live counts")
        try execute(url, sql: "DROP TRIGGER reject_fixture;")
        expect(ledger.retain([event("three")], source: .claude, now: later).saveError == nil,
               "saving recovers after a transient storage failure")

        let brokenURL = root.appendingPathComponent("broken.sqlite3")
        let originalBytes = Data("not a database; preserve me".utf8)
        try originalBytes.write(to: brokenURL)
        let broken = UsageLedger(url: brokenURL).retain([event("live")], source: .claude, now: now)
        expect(broken.saveError != nil && broken.events.count == 1, "unreadable archive preserves current live usage")
        expect(try Data(contentsOf: brokenURL) == originalBytes, "unreadable archive is never reset or overwritten")
        try execute(url, sql: "PRAGMA user_version=99;")
        expect(ledger.retain([event("future-schema")], source: .claude, now: later).saveError != nil,
               "unsupported future schemas are not overwritten")
        expect(try count(url) == beforeFailure + 1, "unsupported schema keeps existing saved events")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        expect(attributes[.posixPermissions] as? Int == 0o600, "token database is readable only by its owner")

        let concurrentURL = root.appendingPathComponent("concurrent.sqlite3")
        _ = UsageLedger(url: concurrentURL).retain([], source: .claude, now: now)
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            _ = UsageLedger(url: concurrentURL).retain([event("concurrent-\(index)")], source: .claude, now: now)
        }
        expect(try count(concurrentURL) == 8, "independent writers preserve each other's counts")

        let logs = root.appendingPathComponent("grok-session")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let line = """
            {"timestamp":"2026-09-08T17:00:00Z","_meta":{"promptId":"call-1","modelUsage":{"grok-test":{"inputTokens":5000,"outputTokens":200,"cacheReadTokens":4000,"cacheCreationTokens":0}}}}
            """
        let sourceFile = logs.appendingPathComponent("updates.jsonl")
        try Data(line.utf8).write(to: sourceFile)
        let integrationURL = root.appendingPathComponent("integration.sqlite3")
        let captured = UsageLedger(url: integrationURL).retain(GrokLogReader.scan(lookbackDays: nil, root: logs, now: later).events,
                                                              source: .grok, now: later)
        expect(captured.saveError == nil && total(captured.events) == 5200, "real provider parser archives the recorded token counts")
        try FileManager.default.removeItem(at: sourceFile)
        let rescanned = GrokLogReader.scan(lookbackDays: nil, root: logs, now: later)
        expect(rescanned.events.isEmpty, "provider fixture reproduces source-log deletion")
        let retained = UsageLedger(url: integrationURL).retain(rescanned.events, source: .grok, now: later)
        let afterDeletion = CostSummary.summarize(events: retained.events, now: later, includeAllHistory: true)
        expect(afterDeletion.dailyTokens.reduce(0) { $0 + $1.tokens } == 5200,
               "provider-log deletion and archive reopen leave chart totals intact")

        let claudeRoot = root.appendingPathComponent("claude-project")
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        func claudeRow(_ id: String, input: Int = 100, output: Int, timestamp: String = "2026-01-09T01:00:00Z") -> String {
            """
            {"type":"assistant","timestamp":"\(timestamp)","requestId":"\(id)","message":{"id":"\(id)","model":"claude-sonnet-4-6","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":30,"cache_read_input_tokens":400}}}
            """
        }
        let claudeFile = claudeRoot.appendingPathComponent("session.jsonl")
        try Data([claudeRow("call", output: 10), claudeRow("call", output: 30), claudeRow("call", output: 10)].joined(separator: "\n").utf8).write(to: claudeFile)
        let finalClaude = ClaudeLogReader.scan(lookbackDays: nil, roots: [claudeRoot])
        expect(finalClaude.count == 1 && finalClaude.first?.outputTokens == 30,
               "Claude streaming repeats retain the most complete actual usage row")
        try Data([claudeRow("call", output: 30), claudeRow("call", input: 200, output: 20)].joined(separator: "\n").utf8).write(to: claudeFile)
        let conflicting = ClaudeLogReader.scan(lookbackDays: nil, roots: [claudeRoot])
        expect(conflicting.first?.inputTokens == 100 && conflicting.first?.outputTokens == 30,
               "incomparable Claude rows never synthesize a larger token vector")
        try Data([claudeRow("", output: 10), claudeRow("", output: 30, timestamp: "2026-01-09T02:00:00Z")].joined(separator: "\n").utf8).write(to: claudeFile)
        let anonymous = ClaudeLogReader.scan(lookbackDays: nil, roots: [claudeRoot])
        let anonymousLedger = UsageLedger(url: root.appendingPathComponent("claude.sqlite3"))
        _ = anonymousLedger.retain(anonymous, source: .claude, now: now)
        try Data(claudeRow("", output: 30, timestamp: "2026-01-09T02:00:00Z").utf8).write(to: claudeFile)
        let truncatedClaude = anonymousLedger.retain(ClaudeLogReader.scan(lookbackDays: nil, roots: [claudeRoot]), source: .claude, now: now)
        expect(truncatedClaude.events.count == 2 && total(truncatedClaude.events) == total(anonymous),
               "Claude records without message IDs survive partial log truncation without recounting")

        let codexRoot = root.appendingPathComponent("codex-sessions")
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        let context = "{\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-5.4\"}}"
        func codexRow(_ timestamp: String, output: Int) -> String {
            """
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":\(output)}}}}
            """
        }
        let codexFile = codexRoot.appendingPathComponent("rollout-session.jsonl")
        let codexFirst = codexRow("2026-01-09T01:00:00Z", output: 20)
        let codexSecond = codexRow("2026-01-09T02:00:00Z", output: 40)
        try Data([context, codexFirst, codexSecond].joined(separator: "\n").utf8).write(to: codexFile)
        let codexLedger = UsageLedger(url: root.appendingPathComponent("codex.sqlite3"))
        _ = codexLedger.retain(CodexLogReader.scan(lookbackDays: nil, root: codexRoot), source: .codex, now: now)
        try Data([context, codexSecond].joined(separator: "\n").utf8).write(to: codexFile)
        let retainedCodex = codexLedger.retain(CodexLogReader.scan(lookbackDays: nil, root: codexRoot), source: .codex, now: now)
        expect(retainedCodex.events.count == 2 && total(retainedCodex.events) == 260,
               "Codex event identity survives truncated source logs")

        let start = Date(timeIntervalSince1970: 1_767_884_400)
        let historicalDay = HistoricalUsageDay(provider: .claude, sourceIdentity: "verified-old-cache-day",
                                               intervalStart: start, intervalEnd: start.addingTimeInterval(86400),
                                               sourceLocalDate: "2026-01-09", sourceUTCOffsetSeconds: 32400,
                                               tokensIncludingCache: 1000, inputPlusOutputTokens: 100)
        expect(historicalDay.isValid, "historical daily interval matches its original calendar date")
        let historyURL = root.appendingPathComponent("historical.sqlite3")
        let historyLedger = UsageLedger(url: historyURL)
        try historyLedger.importHistoricalDays([historicalDay], capturedAt: now)
        try historyLedger.importHistoricalDays([historicalDay], capturedAt: now)
        let historicalSaved = UsageLedger(url: historyURL).retain([], source: .claude, now: now)
        expect(historicalSaved.saveError == nil && historicalSaved.historicalDays.count == 1,
               "historical aggregates persist separately and import idempotently")
        var chicago = Calendar(identifier: .gregorian)
        chicago.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        let exactCall = event("recovered-call", date: start.addingTimeInterval(3600))
        let supplements = HistoricalUsageDay.supplements(historicalSaved.historicalDays, events: [exactCall], calendar: chicago)
        expect(supplements.count == 1 && supplements.first?.tokens == 450 && supplements.first?.billableTokens == 0,
               "only the aggregate residual is added after subtracting detailed overlap")
        expect(supplements.first.map { chicago.component(.day, from: $0.dayStart) } == 9,
               "recovered daily totals retain January 9 instead of being guessed into Chicago January 8")
        let noOverlap = HistoricalUsageDay.supplements([historicalDay], events: [event("outside", date: start.addingTimeInterval(-1))], calendar: chicago)
        expect(noOverlap.first?.tokens == 1000, "overlap uses the original UTC interval, not the display date")
        let fullDetail = HistoricalUsageDay.supplements([historicalDay], events: [event("more", input: 1000, date: start)], calendar: chicago)
        expect(fullDetail.isEmpty, "complete or larger detailed usage supersedes the historical aggregate")
        let recoveredSummary = CostSummary.summarize(events: [exactCall], now: now, includeAllHistory: true, historicalDays: [historicalDay])
        expect(recoveredSummary.dailyTokens.reduce(0) { $0 + $1.tokens } == 1000,
               "the chart does not add a recovered daily total to the same detailed usage twice")
        expect(recoveredSummary.dailyTokens.compactMap(\.recoveredTokens).reduce(0, +) == 450
               && recoveredSummary.dailyTokens.compactMap(\.unpricedTokens).reduce(0, +) == 450,
               "recovered remainder has no invented model price")
        let overlapDay = HistoricalUsageDay(provider: .claude, sourceIdentity: "overlap",
                                            intervalStart: start.addingTimeInterval(43200), intervalEnd: start.addingTimeInterval(129600),
                                            sourceLocalDate: "2026-01-09", sourceUTCOffsetSeconds: -10800,
                                            tokensIncludingCache: 2000, inputPlusOutputTokens: 200)
        var rejectedOverlap = false
        do { try historyLedger.importHistoricalDays([overlapDay], capturedAt: now) } catch { rejectedOverlap = true }
        expect(rejectedOverlap && historyLedger.retain([], source: .claude, now: now).historicalDays.count == 1,
               "overlapping recovered intervals fail without modifying saved history")
        var rejectedDuplicates = false
        do { try historyLedger.importHistoricalDays([historicalDay, historicalDay], capturedAt: now) } catch { rejectedDuplicates = true }
        expect(rejectedDuplicates, "duplicate recovery intervals are rejected without a crash")
        let staleImportLedger = UsageLedger(url: root.appendingPathComponent("stale-import.sqlite3"))
        let longer = HistoricalUsageDay(provider: .claude, sourceIdentity: "longer", intervalStart: start,
                                        intervalEnd: start.addingTimeInterval(90000), sourceLocalDate: "2026-01-09",
                                        sourceUTCOffsetSeconds: 32400, tokensIncludingCache: 1000, inputPlusOutputTokens: 100)
        let shorter = HistoricalUsageDay(provider: .claude, sourceIdentity: "shorter", intervalStart: start,
                                         intervalEnd: start.addingTimeInterval(82800), sourceLocalDate: "2026-01-09",
                                         sourceUTCOffsetSeconds: 32400, tokensIncludingCache: 900, inputPlusOutputTokens: 90)
        let adjacent = HistoricalUsageDay(provider: .claude, sourceIdentity: "adjacent",
                                          intervalStart: start.addingTimeInterval(82800), intervalEnd: start.addingTimeInterval(169200),
                                          sourceLocalDate: "2026-01-10", sourceUTCOffsetSeconds: 36000,
                                          tokensIncludingCache: 800, inputPlusOutputTokens: 80)
        try staleImportLedger.importHistoricalDays([longer], capturedAt: now)
        var rejectedStaleOverlap = false
        do {
            try staleImportLedger.importHistoricalDays([shorter, adjacent], capturedAt: now.addingTimeInterval(-1))
        } catch { rejectedStaleOverlap = true }
        expect(rejectedStaleOverlap && staleImportLedger.retain([], source: .claude, now: now).historicalDays.count == 1,
               "a stale shorter interval cannot hide overlap with the actual saved interval")
        let historicalNow = start.addingTimeInterval(72000)
        let futureWithinDay = event("future-inside-history", date: historicalNow.addingTimeInterval(3600))
        let clockSafe = CostSummary.summarize(events: [futureWithinDay], now: historicalNow, includeAllHistory: true,
                                             historicalDays: [historicalDay])
        expect(clockSafe.dailyTokens.reduce(0) { $0 + $1.tokens } == 1000,
               "excluded future events cannot suppress a recovered aggregate")
        print("PASS: \(checks) usage-ledger checks")
    }
}
