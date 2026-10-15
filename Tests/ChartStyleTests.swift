import Foundation

@main
@MainActor
struct ChartStyleTests {
    static func main() {
        let suite = "dev.codexisland.chart-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Could not create test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let styleKey = "chart"
        let cycleKey = "cycled"
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func store() -> StylePreferenceStore<ChartStyle> {
            StylePreferenceStore(styleKey: styleKey, cycledKey: cycleKey, defaultStyle: .ring,
                                 legacyStyles: ChartStyle.legacyStyles, defaults: defaults)
        }
        check(ChartStyle.allCases == [.rails, .ring, .capacity, .telemetry, .stepped], "Only the selected five charts may be cycled")
        for (raw, expected) in [("ring", ChartStyle.ring), ("bar", .rails), ("spark", .telemetry),
                                ("stepped", .stepped), ("capacity", .capacity), ("invalid", .ring)] {
            defaults.set(raw, forKey: styleKey)
            defaults.set(true, forKey: cycleKey)
            defaults.set("retained", forKey: "unrelated")
            let pref = store()
            check(pref.style == expected, "Saved style \(raw) must resolve to \(expected)")
            check(pref.hasCycledStyle, "Style migration must preserve onboarding state")
            check(defaults.string(forKey: "unrelated") == "retained", "Migration must not clear unrelated preferences")
            if ChartStyle.legacyStyles[raw] != nil {
                check(defaults.string(forKey: styleKey) == expected.rawValue, "Migrated style must persist across launches")
                check(store().style == expected, "A second launch must retain the migration")
            }
        }
        defaults.set("rails", forKey: styleKey)
        defaults.set(false, forKey: cycleKey)
        let pref = store()
        for expected in [ChartStyle.ring, .capacity, .telemetry, .stepped, .rails] {
            pref.cycle()
            check(pref.style == expected, "Cycle must visit every selected chart and wrap")
            check(defaults.string(forKey: styleKey) == expected.rawValue, "Cycle must persist selection")
        }
        check(pref.hasCycledStyle, "Cycling completes the onboarding hint")
        print("PASS \(checks) chart style migration and cycle checks")
    }
}
