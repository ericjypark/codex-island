import Foundation
import Combine

/// One observed reading of a single rate-limit window. `used` is the 0...1
/// fraction the API reported at `at`.
struct UsageSample: Codable {
    let at: Date
    let used: Double
}

/// Records the usage percentages the app already polls so the history chart can
/// plot the user's real trajectory instead of a synthesized curve. Neither
/// provider exposes a usage time-series, but we sample one ourselves on every
/// successful refresh and persist it across launches. A failed poll, a
/// rate-limit cooldown, or a closed app leaves a gap rather than a fabricated
/// point — the chart only ever shows readings that actually happened.
@MainActor
final class UsageHistoryStore: ObservableObject {
    static let shared = UsageHistoryStore()

    /// Bumped whenever a sample lands so SwiftUI tiles observing the store
    /// re-read. The samples themselves stay private — callers ask per series.
    @Published private(set) var revision = 0

    /// Keep a week of readings. At the 5-minute polling floor that is ~2000
    /// points per window, so a count cap also guards against a tighter
    /// interval filling memory.
    private static let maxAge: TimeInterval = 7 * 86400
    private static let maxSamples = 1000
    private static let storageKey = "CodexIsland.usageHistory.v1"
    private static let ownersKey = "CodexIsland.usageHistoryOwners.v1"

    private var series: [String: [UsageSample]]
    /// The account scope that last recorded each provider's series, so a
    /// seed never paints one account's history under another account.
    private var owners: [String: String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: [UsageSample]].self, from: data) {
            series = decoded
        } else {
            series = [:]
        }
        owners = defaults.dictionary(forKey: Self.ownersKey) as? [String: String] ?? [:]
    }

    /// Append the non-errored windows of a fresh fetch. Errored windows are
    /// skipped so a failed poll leaves a gap rather than a fabricated point.
    func record(provider: AlertEngine.Provider, usage: AppUsage, at: Date) {
        let windows: [UsageWindow] = [.fiveHour, .weekly, .fableWeekly, .monthly]
        // Another account's first recorded sample starts the provider's
        // series over, so one account's readings never mix with another's.
        // Ownerless history predates owners and could be any account's.
        if usage.accountResolved, owners[provider.rawValue] != PeekWindowStore.scope(provider, usage: usage),
           windows.contains(where: { Self.isRecordable(usage.window($0)) }) {
            for window in windows { series[key(provider, window)] = nil }
        }
        var changed = append(provider, .fiveHour, usage.fiveHour, at)
        changed = append(provider, .weekly, usage.weekly, at) || changed
        changed = append(provider, .fableWeekly, usage.fableWeekly, at) || changed
        changed = append(provider, .monthly, usage.monthly, at) || changed
        if changed {
            if usage.accountResolved {
                owners[provider.rawValue] = PeekWindowStore.scope(provider, usage: usage)
                defaults.set(owners, forKey: Self.ownersKey)
            }
            persist()
            revision &+= 1
        }
    }

    /// Readings for one series, oldest first. The latest entry is the most
    /// recent successful poll.
    func samples(provider: AlertEngine.Provider, window: UsageWindow) -> [UsageSample] {
        samples(key: key(provider, window))
    }

    func samples(key: String) -> [UsageSample] { series[key] ?? [] }

    /// False when the series was recorded for a different account than
    /// `usage` names, or by an unknown one (history from before owners were
    /// kept). Usage whose account isn't resolved yet is allowed.
    func belongs(provider: AlertEngine.Provider, to usage: AppUsage) -> Bool {
        guard usage.accountResolved else { return true }
        guard let owner = owners[provider.rawValue] else {
            return [UsageWindow.fiveHour, .weekly, .fableWeekly, .monthly].allSatisfy { series[key(provider, $0)]?.isEmpty ?? true }
        }
        return owner == PeekWindowStore.scope(provider, usage: usage)
    }

    func record(key: String, window: WindowUsage, at: Date) {
        guard append(key, window, at) else { return }
        persist()
        revision &+= 1
    }

    /// Newest recorded reading for a series, or nil when there is none or the
    /// newest one predates `window.span`. History survives relaunch, so this
    /// is what lets a cold start that lands on a failing endpoint show the
    /// user's last real number instead of a blank tile. The age bound matters:
    /// a 5-hour reading from six hours ago describes a window that has since
    /// reset, and showing it would be a confident lie rather than stale truth.
    func latestReading(
        provider: AlertEngine.Provider, window: UsageWindow, now: Date = Date()
    ) -> UsageSample? {
        guard let newest = series[key(provider, window)]?.last else { return nil }
        guard now.timeIntervalSince(newest.at) <= window.span else { return nil }
        return newest
    }

    private func append(
        _ provider: AlertEngine.Provider,
        _ window: UsageWindow,
        _ reading: WindowUsage,
        _ at: Date
    ) -> Bool {
        append(key(provider, window), reading, at)
    }

    private static func isRecordable(_ reading: WindowUsage) -> Bool {
        reading.error == nil && reading.hasPercentageReading
    }

    private func append(_ k: String, _ reading: WindowUsage, _ at: Date) -> Bool {
        guard Self.isRecordable(reading) else { return false }
        var arr = series[k] ?? []
        arr.append(UsageSample(at: at, used: max(0, min(1, reading.usedPercent))))
        let cutoff = at.addingTimeInterval(-Self.maxAge)
        arr.removeAll { $0.at < cutoff }
        if arr.count > Self.maxSamples { arr.removeFirst(arr.count - Self.maxSamples) }
        series[k] = arr
        return true
    }

    private func key(_ p: AlertEngine.Provider, _ w: UsageWindow) -> String {
        "\(p.rawValue).\(w.rawValue)"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(series) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
