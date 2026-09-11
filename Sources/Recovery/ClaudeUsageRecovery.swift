import CryptoKit
import Foundation

enum ClaudeUsageRecovery {
    struct Options {
        var apply = false
        var help = false
        var projects: [URL] = []
        var preferences: [URL] = []
        var timeZone: TimeZone?

        init() {}

        init(arguments: [String]) throws {
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--apply": apply = true
                case "--help", "-h": help = true
                case "--projects", "--preferences", "--time-zone":
                    index += 1
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw RecoveryError.message("Missing value for \(argument).")
                    }
                    let value = arguments[index]
                    if argument == "--time-zone" {
                        guard let zone = TimeZone(identifier: value) else {
                            throw RecoveryError.message("Unknown timezone: \(value). Use a name such as America/Chicago or Asia/Seoul.")
                        }
                        timeZone = zone
                    } else {
                        let url = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath).standardizedFileURL
                        var directory: ObjCBool = false
                        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
                              directory.boolValue == (argument == "--projects") else {
                            throw RecoveryError.message("\(argument) requires an existing \(argument == "--projects" ? "folder" : "plist file"): \(url.path)")
                        }
                        if argument == "--projects" { projects.append(url) } else { preferences.append(url) }
                    }
                default: throw RecoveryError.message("Unknown option: \(argument). Use --help for usage.")
                }
                index += 1
            }
        }
    }

    struct Candidate {
        let day: HistoricalUsageDay
        let capturedAt: Date
    }

    struct Totals {
        let tokens: Int
        let messages: Int
        let days: Int
    }

    struct Preview {
        let before: Totals
        let after: Totals
        let messageCount: Int
        let dailyCount: Int
        let notices: [String]
        let needsTimeZone: Bool
        fileprivate let events: [TokenEvent]
        fileprivate let candidates: [Candidate]
        fileprivate let ledgerURL: URL

        var additionalTokens: Int { max(0, after.tokens - before.tokens) }
        var hasChanges: Bool {
            after.tokens > before.tokens || after.messages > before.messages || after.days > before.days
        }
    }

    struct Outcome {
        let tokens: Int
        let additionalTokens: Int
        let didSave: Bool
        let backupURL: URL?
    }

    private struct LegacyCache: Decodable {
        let claudeDailyTokens: [DailyTokenBucket]
        let lastUpdated: Date
    }

    enum RecoveryError: Error, LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let text): return text }
        }
    }

    static let help = """
    Recover saved Claude usage into CodexIsland.

    Usage: recover-claude-usage.sh [--apply] [--projects PATH] [--preferences PATH] [--time-zone NAME]

    With no options, preview recovery from configured Claude Code and Cowork logs.
    --apply             Save verified counts after backing up the existing usage archive.
    --projects PATH     Also scan an extracted backup's projects folder; repeat for multiple backups.
    --preferences PATH  Also read an old CodexIsland preferences plist; repeat as needed.
    --time-zone NAME    Original timezone of saved daily snapshots, e.g. Asia/Seoul.
    --help              Show this help.

    Existing CodexIsland daily snapshots are checked automatically. Daily recovery
    requires their original timezone. Only saved counters are used; missing usage
    is never estimated. All counts include cache tokens. No login or network access.
    """

    static func run(arguments: [String], ledger: UsageLedger = .shared,
                    defaultRoots: [URL]? = nil, defaultPreferences: [URL]? = nil,
                    output: (String) -> Void = { print($0) }) -> Int32 {
        do {
            let options = try Options(arguments: arguments)
            if options.help { output(help); return 0 }
            output("Scanning saved Claude records locally…")
            let preview = try prepare(options: options, ledger: ledger, defaultRoots: defaultRoots, defaultPreferences: defaultPreferences)
            preview.notices.forEach(output)
            output("Found \(number(preview.messageCount)) distinct messages with usage IDs and \(number(preview.dailyCount)) saved daily totals.")
            output("Claude tokens already preserved: \(number(preview.before.tokens))")
            output("Claude tokens after recovery:   \(number(preview.after.tokens))")
            output("Additional tokens:              \(number(preview.additionalTokens))")
            output("Counts include cache tokens. Recovered daily totals without model details are left unpriced.")

            guard options.apply else {
                output("Preview only; your saved counts are unchanged. Run again with --apply to save the recovery.")
                return 0
            }
            let outcome = try apply(preview, ledger: ledger, backupCreated: { output("Archive backup: \($0.path)") })
            guard outcome.didSave else {
                output("No additional verified tokens to save. Your usage archive is unchanged.")
                return 0
            }
            output("Saved. Claude tokens now preserved: \(number(outcome.tokens))")
            output("Refresh CodexIsland to include the recovered counts.")
            return 0
        } catch {
            output("Recovery stopped: \(userMessage(for: error))")
            output("Original Claude files were not changed. Any counts already saved remain in the archive.")
            return 1
        }
    }

    static func prepare(options: Options, ledger: UsageLedger = .shared, defaultRoots: [URL]? = nil,
                        defaultPreferences: [URL]? = nil) throws -> Preview {
        for (urls, expectsDirectory) in [(options.projects, true), (options.preferences, false)] {
            for url in urls {
                var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
                      directory.boolValue == expectsDirectory else {
                    throw RecoveryError.message("A selected recovery source is no longer available. Choose it again, then scan.")
                }
            }
        }
        let roots = Array(Set((defaultRoots ?? ClaudeLogReader.projectRoots()) + options.projects)).sorted { $0.path < $1.path }
        let ownPreferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/dev.codexisland.CodexIsland.plist")
        let preferences = Array(Set((defaultPreferences ?? [ownPreferences]) + options.preferences))
            .filter { FileManager.default.fileExists(atPath: $0.path) }.sorted { $0.path < $1.path }
        let now = Date()
        let scanned = ClaudeLogReader.scan(lookbackDays: nil, roots: roots, requireStableIDs: true)
        let events = scanned.filter { event in
            let counts = [event.inputTokens, event.outputTokens, event.cacheCreationTokens, event.cacheReadTokens]
            return event.timestamp.timeIntervalSince1970.isFinite && event.timestamp.timeIntervalSince1970 > 0
                && event.timestamp <= now && counts.allSatisfy { $0 >= 0 && $0 <= Int.max / 4 }
                && counts.contains { $0 > 0 }
        }
        var notices: [String] = []
        if events.count < scanned.count { notices.append("Skipped \(scanned.count - events.count) records with invalid counts or future dates.") }
        var needsTimeZone = false
        let candidates = try dailyCandidates(preferences: preferences, timeZone: options.timeZone, now: now,
                                             output: { notices.append($0) }, timezoneNeeded: { needsTimeZone = true })
        try validateTotals(events: events, days: candidates.map(\.day))
        let result = try simulate(events: events, candidates: candidates, ledger: ledger, now: now)
        return Preview(before: result.before, after: result.after, messageCount: events.count, dailyCount: candidates.count,
                       notices: notices, needsTimeZone: needsTimeZone, events: events, candidates: candidates, ledgerURL: ledger.url)
    }

    static func apply(_ preview: Preview, ledger: UsageLedger = .shared, backupCreated: (URL) -> Void = { _ in }) throws -> Outcome {
        guard preview.ledgerURL.standardizedFileURL == ledger.url.standardizedFileURL else {
            throw RecoveryError.message("The usage archive changed. Scan again before saving.")
        }
        let now = Date()
        // Recheck the current archive against exactly the reviewed records, without re-reading their source files.
        let current = try simulate(events: preview.events, candidates: preview.candidates, ledger: ledger, now: now)
        guard current.after.tokens > current.before.tokens || current.after.messages > current.before.messages
                || current.after.days > current.before.days else {
            return Outcome(tokens: current.before.tokens, additionalTokens: 0, didSave: false, backupURL: nil)
        }
        let backup = ledger.url.deletingLastPathComponent().appendingPathComponent("Recovery Backups", isDirectory: true)
            .appendingPathComponent("usage-history-\(UUID().uuidString).sqlite3")
        let backedUp = try ledger.copyDatabase(to: backup)
        if backedUp { backupCreated(backup) }
        let saved = try recover(events: preview.events, candidates: preview.candidates, ledger: ledger, now: now)
        let changed = saved.after.tokens > saved.before.tokens || saved.after.messages > saved.before.messages
            || saved.after.days > saved.before.days
        return Outcome(tokens: saved.after.tokens, additionalTokens: max(0, saved.after.tokens - saved.before.tokens),
                       didSave: changed, backupURL: backedUp ? backup : nil)
    }

    static func userMessage(for error: Error) -> String {
        if let error = error as? RecoveryError { return error.localizedDescription }
        return "Could not read or save usage history. Check file access and available disk space, then scan again."
    }

    private static func simulate(events: [TokenEvent], candidates: [Candidate], ledger: UsageLedger, now: Date) throws -> (before: Totals, after: Totals) {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("codexisland-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let scratch = UsageLedger(url: temporary.appendingPathComponent("preview.sqlite3"))
        try ledger.copyDatabase(to: scratch.url)
        let before = try snapshot(ledger: scratch, now: now)
        let result = try recover(events: events, candidates: candidates, ledger: scratch, now: now)
        return (before, result.after)
    }

    static func dailyCandidates(preferences: [URL], timeZone: TimeZone?, now: Date,
                                output: (String) -> Void, timezoneNeeded: () -> Void = {}) throws -> [Candidate] {
        var candidates: [Date: Candidate] = [:]
        var conflicts: Set<Date> = []
        for url in preferences {
            let data = try Data(contentsOf: url)
            guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw RecoveryError.message("Could not read preferences: \(url.path)")
            }
            cacheLoop: for version in 4...7 {
                let key = "MacIsland.costCache.v\(version)"
                guard let cache = values[key] as? Data else { continue }
                guard let saved = try? JSONDecoder().decode(LegacyCache.self, from: cache),
                      saved.lastUpdated.timeIntervalSince1970.isFinite,
                      saved.lastUpdated.timeIntervalSince1970 > 0, saved.lastUpdated <= now else {
                    output("Skipped \(key): no supported, dated daily snapshot.")
                    continue
                }
                guard saved.claudeDailyTokens.contains(where: { $0.tokens > 0 }) else { continue }
                guard !saved.claudeDailyTokens.contains(where: { ($0.recoveredTokens ?? 0) > 0 }) else {
                    output("Skipped \(key): already contains recovered aggregates.")
                    continue
                }
                guard let timeZone else {
                    timezoneNeeded()
                    output("Found \(key) daily totals. Add --time-zone with their original timezone to include them.")
                    continue
                }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                let digest = SHA256.hash(data: cache).map { String(format: "%02x", $0) }.joined()
                var incoming: [Candidate] = []
                var seen: Set<Date> = []
                for bucket in saved.claudeDailyTokens where bucket.tokens != 0 {
                    let start = bucket.dayStart
                    guard calendar.startOfDay(for: start) == start else {
                        output("Skipped \(key): daily boundaries do not match \(timeZone.identifier). Use the snapshot's original timezone.")
                        continue cacheLoop
                    }
                    guard start <= saved.lastUpdated,
                          let end = calendar.date(byAdding: .day, value: 1, to: start),
                          seen.insert(start).inserted else {
                        throw RecoveryError.message("\(key) has invalid or repeated daily dates; nothing was imported.")
                    }
                    let parts = calendar.dateComponents([.year, .month, .day], from: start)
                    guard let year = parts.year, let month = parts.month, let day = parts.day else { continue }
                    let record = HistoricalUsageDay(provider: .claude, sourceIdentity: "\(key):\(digest):\(start.timeIntervalSince1970)",
                        intervalStart: start, intervalEnd: end,
                        sourceLocalDate: String(format: "%04d-%02d-%02d", year, month, day),
                        sourceUTCOffsetSeconds: timeZone.secondsFromGMT(for: start),
                        tokensIncludingCache: bucket.tokens, inputPlusOutputTokens: bucket.billableTokens)
                    guard record.isValid else { throw RecoveryError.message("\(key) contains invalid token counts or dates; nothing was imported.") }
                    incoming.append(Candidate(day: record, capturedAt: saved.lastUpdated))
                }
                for candidate in incoming {
                    let start = candidate.day.intervalStart
                    guard !conflicts.contains(start) else { continue }
                    if let previous = candidates[start] {
                        let old = previous.day, new = candidate.day
                        if old.intervalEnd != new.intervalEnd {
                            candidates.removeValue(forKey: start)
                            conflicts.insert(start)
                        } else if new.tokensIncludingCache >= old.tokensIncludingCache,
                                  new.inputPlusOutputTokens >= old.inputPlusOutputTokens {
                            candidates[start] = candidate
                        } else if old.tokensIncludingCache < new.tokensIncludingCache
                                    || old.inputPlusOutputTokens < new.inputPlusOutputTokens {
                            candidates.removeValue(forKey: start)
                            conflicts.insert(start)
                        }
                    } else { candidates[start] = candidate }
                }
            }
        }
        if !conflicts.isEmpty { output("Skipped \(conflicts.count) days with conflicting saved counters.") }
        return candidates.values.sorted { $0.day.intervalStart < $1.day.intervalStart }
    }

    private static func recover(events: [TokenEvent], candidates: [Candidate], ledger: UsageLedger, now: Date) throws -> (before: Totals, after: Totals) {
        let batches = Dictionary(grouping: candidates, by: \.capturedAt).map {
            UsageLedger.HistoricalBatch(days: $0.value.map(\.day), capturedAt: $0.key)
        }
        let saved = try ledger.recoverClaude(events, historicalBatches: batches, now: now)
        return try (summarize(saved.before, now: now), summarize(saved.after, now: now))
    }

    private static func snapshot(ledger: UsageLedger, now: Date) throws -> Totals {
        let claude = try ledger.savedSnapshot(source: .claude)
        let openCode = try ledger.savedSnapshot(source: .openCode)
        return try summarize(UsageLedger.Snapshot(events: claude.events + openCode.events.filter { $0.provider == .claude },
                                                  saveError: nil, historicalDays: claude.historicalDays), now: now)
    }

    private static func summarize(_ saved: UsageLedger.Snapshot, now: Date) throws -> Totals {
        let events = saved.events.filter { $0.timestamp <= now }
        let days = saved.historicalDays.filter { $0.intervalStart <= now }
        try validateTotals(events: events, days: days)
        let detailed = events.reduce(0) { $0 + $1.inputTokens + $1.outputTokens + $1.cacheCreationTokens + $1.cacheReadTokens }
        let residual = HistoricalUsageDay.supplements(days, events: events, calendar: .current).reduce(0) { $0 + $1.tokens }
        return Totals(tokens: detailed + residual, messages: events.count, days: days.count)
    }

    private static func validateTotals(events: [TokenEvent], days: [HistoricalUsageDay]) throws {
        var total = 0
        let counts = events.flatMap { [$0.inputTokens, $0.outputTokens, $0.cacheCreationTokens, $0.cacheReadTokens] }
            + days.map(\.tokensIncludingCache)
        for count in counts {
            let result = total.addingReportingOverflow(count)
            guard count >= 0, !result.overflow, result.partialValue <= Int.max / 4 else {
                throw RecoveryError.message("Saved token counts exceed the supported range. Check the recovery files before trying again.")
            }
            total = result.partialValue
        }
    }

    private static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
