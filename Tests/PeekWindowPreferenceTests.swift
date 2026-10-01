import Foundation
import Combine

@main
@MainActor
struct PeekWindowPreferenceTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        let fiveReset = Date(timeIntervalSince1970: 2_000_000_000)
        let weekReset = fiveReset.addingTimeInterval(604800)
        let five = WindowUsage(usedPercent: 0.12, resetAt: fiveReset, error: nil)
        let week = WindowUsage(usedPercent: 0.87, resetAt: weekReset, error: nil)
        let both = AppUsage(fiveHour: five, weekly: week, reportedWindows: [.fiveHour, .weekly])
        check(both.peekWindowKind(preference: .auto) == .fiveHour, "Auto preserves five-hour priority")
        for preference in [PeekWindowPreference.fiveHour, .weekly] {
            let reading = both.peekWindow(preference: preference)
            let weekly = preference == .weekly
            check(both.peekWindowKind(preference: preference) == (weekly ? .weekly : .fiveHour),
                  "Window labels follow the explicit choice")
            check(reading.usedPercent == (weekly ? 0.87 : 0.12), "Selection changes the actual reading")
            check(reading.resetAt == (weekly ? weekReset : fiveReset), "Reset time belongs to the chosen window")
            check(reading.displayedPercentInt(mode: .remaining) == (weekly ? 13 : 88), "Remaining mode uses the chosen reading")
            check(reading.displayedPercentInt(mode: .used) == (weekly ? 87 : 12), "Used mode uses the chosen reading")
        }
        check(both.visibleWindows == [.fiveHour, .weekly], "Selection leaves expanded windows intact")
        let weeklyOnly = AppUsage(fiveHour: five, weekly: week, reportedWindows: [.weekly])
        check(weeklyOnly.peekWindowKind(preference: .auto) == .weekly, "Weekly-only plan retains automatic fallback")
        check(!weeklyOnly.peekWindow(preference: .fiveHour).hasReading, "Unreported window cannot reuse stale five-hour data")
        check(weeklyOnly.peekWindowKind(preference: .fiveHour) == .fiveHour, "Unavailable explicit window keeps its label")
        let fiveOnly = AppUsage(fiveHour: five, weekly: .unknown, reportedWindows: [.fiveHour])
        check(!fiveOnly.peekWindow(preference: .weekly).hasReading, "Explicit weekly choice does not silently show five-hour usage")
        let failed = WindowUsage(usedPercent: 0, resetAt: nil, error: "HTTP 500")
        let partial = AppUsage(fiveHour: failed, weekly: week, reportedWindows: [.fiveHour, .weekly])
        check(partial.peekWindowKind(preference: .auto) == .weekly, "Auto still falls back after a failed five-hour reading")
        check(partial.peekWindow(preference: .fiveHour).error == "HTTP 500", "Explicit selection retains its fetch error")
        check(!partial.peekWindow(preference: .fiveHour).hasReading, "Failure does not become a real zero")
        let zero = AppUsage(fiveHour: WindowUsage(usedPercent: 0, resetAt: fiveReset, error: nil), weekly: week)
        check(zero.peekWindowKind(preference: .auto) == .fiveHour, "A genuine zero does not trigger fallback")
        check(zero.peekWindow(preference: .fiveHour).displayedPercentInt(mode: .remaining) == 100,
              "A genuine zero still means 100 percent remaining")
        for preference in PeekWindowPreference.allCases {
            check(!AppUsage.empty.peekWindow(preference: preference).hasReading, "Cold start stays unknown")
        }
        let stale = WindowUsage(usedPercent: 0.87, resetAt: weekReset, error: "offline")
        let retained = AppUsage(fiveHour: five, weekly: stale)
        check(retained.peekWindow(preference: .weekly).hasReading, "Retained usage remains a reading")
        check(retained.peekWindow(preference: .weekly).error == "offline", "Retained error survives selection")
        let monthly = WindowUsage(usedPercent: 0.96, resetAt: nil, error: nil, usedAmount: 96, limitAmount: 100)
        let enterprise = AppUsage(fiveHour: .unknown, weekly: .unknown, monthly: monthly, reportedWindows: [.monthly])
        check(enterprise.peekWindowKind(preference: .auto) == .monthly, "Auto preserves monthly-only Enterprise support")
        check(enterprise.peekWindow(preference: .auto).usedAmount == 96, "Auto preserves Enterprise credit amounts")
        check(!enterprise.peekWindow(preference: .weekly).hasReading, "Explicit weekly choice cannot relabel monthly credits")
        let none = AppUsage(fiveHour: five, weekly: week, reportedWindows: [])
        check(!none.peekWindow(preference: .auto).hasReading, "Explicitly empty discovery cannot expose stale usage")

        let suite = "dev.codexisland.peek-window-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("retained", forKey: "unrelated")
        let store = PeekWindowPreferenceStore(defaults: defaults)
        check(store.preference(for: .claude) == .auto && store.preference(for: .codex) == .auto,
              "Existing installations default to Auto for both providers")
        var changes = 0
        let observation = store.objectWillChange.sink { changes += 1 }
        store.set(.weekly, for: .claude)
        check(changes == 1, "Preference changes notify live views and alerts")
        check(store.preference(for: .codex) == .auto, "Claude selection does not change Codex")
        store.set(.fiveHour, for: .codex)
        let reloaded = PeekWindowPreferenceStore(defaults: defaults)
        check(reloaded.preference(for: .claude) == .weekly, "Claude choice survives relaunch")
        check(reloaded.preference(for: .codex) == .fiveHour, "Codex choice survives relaunch independently")
        store.set(.auto, for: .claude)
        check(PeekWindowPreferenceStore(defaults: defaults).preference(for: .claude) == .auto, "Returning to Auto persists")
        check(defaults.string(forKey: "unrelated") == "retained", "Unrelated preferences are preserved")
        store.set(.weekly, for: .grok)
        store.set(.weekly, for: .antigravity)
        check(store.preference(for: .grok) == .auto && store.preference(for: .antigravity) == .auto,
              "Connected providers keep their existing primary metric settings")
        defaults.set(["claude": "future-value", "codex": "weekly"], forKey: "MacIsland.peekWindows")
        let future = PeekWindowPreferenceStore(defaults: defaults)
        check(future.preference(for: .claude) == .auto, "Invalid preference falls back to Auto")
        check(future.preference(for: .codex) == .weekly, "One invalid preference does not reset the other provider")
        defaults.set("malformed", forKey: "MacIsland.peekWindows")
        check(PeekWindowPreferenceStore(defaults: defaults).preference(for: .claude) == .auto,
              "Malformed persisted data is harmless")
        observation.cancel()
        print("PASS \(checks) peek window preference checks")
    }
}
