import Foundation

@main
struct EnterpriseUsageTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if !condition { failures += 1 }
    }

    static func parse(_ json: String) -> WindowUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return nil }
        return UsageFetcher.parseClaudeEnterpriseCredits(object)
    }

    @MainActor static func main() {
        UsageStore.shared.injectPreviewUsage(claudePercent: 0.85, codexPercent: 0.97)
        for preference in PeekWindowPreference.allCases {
            expect(UsageStore.shared.claude.peekWindow(preference: preference).percentInt == 85,
                   "Claude alert preview follows \(preference) choice")
            expect(UsageStore.shared.codex.peekWindow(preference: preference).percentInt == 97,
                   "Codex alert preview follows \(preference) choice")
        }
        expect(UsageWindow.monthly.labelKey == "Credits", "monthly credits cannot use the weekly label")
        let staleCaption = UsageChartsRow(color: .white, style: .ring, seed: 0, metrics: [])
            .caption(WindowUsage(usedPercent: 0.4, resetAt: nil, error: "HTTP 500", usedAmount: 6.4, limitAmount: 16))
        expect(staleCaption.hasPrefix("HTTP 500"), "monthly fetch error stays visible in narrow captions")
        let limited = parse(#"{"is_enabled":true,"used_credits":47,"monthly_limit":1600,"currency":"USD"}"#)!
        expect(limited.usedAmount == 0.47 && limited.limitAmount == 16, "API cents convert once to major units")
        expect(abs(limited.usedPercent - 47.0 / 1600) < 0.000001, "utilization uses raw cents")
        expect(limited.resetAt == nil, "missing provider reset stays unknown")
        expect(limited.hasPercentageReading, "limited amount has a percentage")
        let percent = parse(#"{"is_enabled":true,"used_credits":47,"monthly_limit":1600,"utilization":0.5}"#)!
        expect(percent.usedPercent == 0.005, "fractional percentage is normalized correctly")
        let epoch = parse(#"{"is_enabled":true,"used_credits":47,"monthly_limit":1600,"resets_at":1800000000}"#)!
        expect(epoch.resetAt == Date(timeIntervalSince1970: 1800000000), "provider epoch reset retained")
        let iso = parse(#"{"is_enabled":true,"used_credits":47,"monthly_limit":1600,"resets_at":"2027-01-15T08:30:00.000Z"}"#)!
        expect(iso.resetAt != nil, "provider ISO reset retained")
        expect(parse(#"{"is_enabled":false,"used_credits":47}"#) == nil, "disabled credits omitted")
        expect(parse(#"{"is_enabled":true,"monthly_limit":1600}"#) == nil, "missing spend is not zero")
        expect(parse(#"{"is_enabled":true,"used_credits":-1}"#) == nil, "negative spend rejected")
        expect(parse(#"{"is_enabled":true,"used_credits":1,"monthly_limit":-1}"#) == nil, "negative limit rejected")
        expect(parse(#"{"is_enabled":true,"used_credits":47}"#) == nil, "missing monthly limit is unknown rather than unlimited")
        expect(parse(#"{"is_enabled":true,"used_credits":0}"#) == nil, "zero spend with missing limit is not an unlimited claim")
        let unlimited = parse(#"{"is_enabled":true,"used_credits":47,"monthly_limit":null}"#)!
        expect(unlimited.hasReading && !unlimited.hasPercentageReading, "unlimited spend has no fabricated percentage")
        expect(unlimited.isUnlimitedAmount, "unlimited amount identified")
        let zero = parse(#"{"is_enabled":true,"used_credits":0,"monthly_limit":1600}"#)!
        expect(zero.hasReading && zero.hasPercentageReading && zero.usedPercent == 0, "real zero remains a reading")
        expect(parse(#"{"is_enabled":true,"used_credits":47,"monthly_limit":"unknown"}"#) == nil, "malformed limit is not unlimited")
        let closed = parse(#"{"is_enabled":true,"used_credits":0,"monthly_limit":0}"#)!
        expect(!closed.isUnlimitedAmount && closed.usedPercent == 1, "zero spend cap is exhausted rather than unlimited")
        let reportedZeroCap = parse(#"{"is_enabled":true,"used_credits":0,"monthly_limit":0,"utilization":0}"#)!
        expect(reportedZeroCap.usedPercent == 1 && reportedZeroCap.displayedFraction(mode: .remaining) == 0,
               "zero credit cap overrides a reported zero utilization")

        let en = Locale(identifier: "en_US")
        expect(UsageCreditDisplay.compactCurrency(1_000, code: "USD", locale: en) == "$1k", "notch abbreviates thousand-dollar spend")
        expect(UsageCreditDisplay.compactCurrency(12_345.67, code: "USD", locale: en) == "$12.3k", "notch keeps large spend compact")
        expect(UsageCreditDisplay.compactCurrency(999_950, code: "USD", locale: en) == "$1M", "notch abbreviation promotes rounded unit boundary")
        expect(UsageCreditDisplay.compactCurrency(0.47, code: "USD", locale: en) == "$0.47", "small credit amount retains exact cents")
        let swedish = UsageCreditDisplay.compactCurrency(12_345.67, code: "SEK", locale: Locale(identifier: "sv_SE"))
        expect(swedish.hasPrefix("12,3k") && swedish.hasSuffix("kr"), "notch preserves localized currency placement")

        let failure = WindowUsage(usedPercent: 0, resetAt: nil, error: "HTTP 500")
        let failed = AppUsage(fiveHour: failure, weekly: failure, monthly: failure)
        expect(failed.visibleWindows == [.fiveHour, .weekly], "failed Codex cold start has no unsupported monthly tile")
        let original = AppUsage(fiveHour: .unknown, weekly: .unknown, monthly: limited, plan: "enterprise", reportedWindows: [.monthly])
        let retained = AppUsage.merged(fetched: failed, retaining: original, at: Date())
        expect(retained.monthly.usedAmount == 0.47 && retained.monthly.limitAmount == 16, "failed refresh preserves credit amounts")
        expect(retained.monthly.error == "HTTP 500" && retained.visibleWindows == [.monthly], "failed refresh preserves monthly identity and error")
        let expired = AppUsage(fiveHour: .unknown, weekly: .unknown, monthly: WindowUsage(usedPercent: 0.9, resetAt: Date(timeIntervalSince1970: 1), error: nil, usedAmount: 9, limitAmount: 10))
        expect(!AppUsage.merged(fetched: failed, retaining: expired, at: Date()).monthly.hasReading, "expired credit period is not carried forward")
        expect(!AppUsage.merged(fetched: .empty, retaining: original, at: Date()).monthly.hasReading, "omitted monthly window displaces old reading")

        let weeklyFallback = AppUsage(fiveHour: failure, weekly: limited, reportedWindows: [.fiveHour, .weekly])
        expect(weeklyFallback.peekWindowKind == .weekly, "unavailable 5h reading still falls back to real weekly reading")
        let response = try! JSONSerialization.jsonObject(with: Data(#"{"extra_usage":{"is_enabled":true,"used_credits":47,"monthly_limit":1600}}"#.utf8)) as! [String: Any]
        let noPlan = UsageFetcher.parseClaudeUsageResponse(response, plan: nil)
        expect(noPlan.visibleWindows == [.monthly] && noPlan.monthly.usedAmount == 0.47,
               "enabled credits survive missing optional plan metadata")
        expect(UsageFetcher.parseClaudeUsageResponse(response, plan: "max").monthly.hasReading,
               "response schema determines available credits")
        let reset = Date().addingTimeInterval(3600)
        let preferredUsage = AppUsage(
            fiveHour: WindowUsage(usedPercent: 0.1, resetAt: reset, error: nil),
            weekly: WindowUsage(usedPercent: 0.98, resetAt: reset, error: nil),
            reportedWindows: [.fiveHour, .weekly])
        for provider in [IslandProvider.claude, .codex] {
            let selected = AlertDecision.legacyInputs(provider: provider, usage: preferredUsage,
                preference: .weekly, visible: true)
            expect(selected.count == 1 && selected[0].windowKind == .weekly,
                   "\(provider) alerts use selected weekly identity")
            expect(AlertDecision.computeSeverity(inputs: selected, warning: 80, critical: 95)[provider] == .critical,
                   "\(provider) alerts follow weekly reading rather than low five-hour usage")
            let hourlyInputs = AlertDecision.legacyInputs(provider: provider, usage: preferredUsage,
                preference: .fiveHour, visible: true)
            expect(AlertDecision.computeSeverity(inputs: hourlyInputs, warning: 80, critical: 95)[provider] == nil,
                   "\(provider) changing selection recomputes severity")
            let previous: Set<AlertEngine.CrossingKey> = [
                .init(provider: provider, threshold: .warning, resetAt: reset, windowKind: .fiveHour),
                .init(provider: provider, threshold: .critical, resetAt: reset, windowKind: .fiveHour)]
            let crossing = AlertDecision.evaluateCrossings(previous: previous, inputs: selected,
                warning: 80, critical: 95, warmedUp: true)
            expect(crossing.pulse?.lines.first?.percent == 98, "\(provider) weekly crossing is independent of five-hour crossing")
            expect(AlertDecision.evaluateCrossings(previous: crossing.next, inputs: selected,
                warning: 80, critical: 95, warmedUp: true).pulse == nil,
                   "\(provider) switching back to the same window does not repeat its crossing")
            let hidden = AlertDecision.legacyInputs(provider: provider, usage: preferredUsage,
                preference: .weekly, visible: false)
            expect(AlertDecision.computeSeverity(inputs: hidden, warning: 80, critical: 95).isEmpty,
                   "\(provider) hidden usage does not alert")
        }
        let unavailable = AlertDecision.legacyInputs(provider: .codex,
            usage: AppUsage(fiveHour: preferredUsage.weekly, weekly: preferredUsage.weekly, reportedWindows: [.weekly]),
            preference: .fiveHour, visible: true)
        expect(AlertDecision.computeSeverity(inputs: unavailable, warning: 80, critical: 95).isEmpty,
               "Unavailable explicit window cannot alert on stale data")
        let credits = AppUsage(fiveHour: preferredUsage.fiveHour, weekly: preferredUsage.fiveHour,
            monthly: preferredUsage.weekly, reportedWindows: [.fiveHour, .weekly, .monthly])
        let withCredits = AlertDecision.legacyInputs(provider: .claude, usage: credits, preference: .weekly, visible: true)
        expect(withCredits.map(\.windowKind) == [.weekly, .monthly], "Selected weekly window retains independent monthly credit alerts")
        expect(AlertDecision.computeSeverity(inputs: withCredits, warning: 80, critical: 95)[.claude] == .critical,
               "Monthly exhaustion still alerts when selected weekly usage is low")
        let monthlyOnly = AlertDecision.legacyInputs(provider: .claude, usage: original, preference: .auto, visible: true)
        expect(monthlyOnly.map(\.windowKind) == [.monthly], "Auto monthly selection is not duplicated in alerts")
        let monthly = AlertDecision.WindowInput(provider: .claude, visible: true,
            window: WindowUsage(usedPercent: 0.98, resetAt: reset, error: nil), windowKind: .monthly)
        let hourly = AlertDecision.WindowInput(provider: .claude, visible: true,
            window: WindowUsage(usedPercent: 0.1, resetAt: reset, error: nil))
        expect(AlertDecision.computeSeverity(inputs: [monthly, hourly], warning: 80, critical: 95)[.claude] == .critical, "monthly exhaustion alerts independently of low 5h usage")
        expect(AlertDecision.computeSeverity(inputs: [hourly, monthly], warning: 80, critical: 95)[.claude] == .critical, "severity aggregation is order independent")
        let amountInput = AlertDecision.WindowInput(provider: .claude, visible: true, window: unlimited, windowKind: .monthly)
        expect(AlertDecision.computeSeverity(inputs: [amountInput], warning: 80, critical: 95).isEmpty, "unlimited spend cannot trigger a quota alert")
        let first = AlertDecision.evaluateCrossings(previous: [], inputs: [monthly, hourly], warning: 80, critical: 95, warmedUp: true)
        expect(first.pulse?.severity == .critical, "monthly crossing emits a pulse with known reset")
        let repeatPoll = AlertDecision.evaluateCrossings(previous: first.next, inputs: [monthly, hourly], warning: 80, critical: 95, warmedUp: true)
        expect(repeatPoll.pulse == nil, "another window cannot erase monthly crossing memory")
        let hourlyReset = AlertDecision.WindowInput(provider: .claude, visible: true,
            window: WindowUsage(usedPercent: 0.1, resetAt: reset.addingTimeInterval(300), error: nil))
        let otherReset = AlertDecision.evaluateCrossings(previous: first.next, inputs: [monthly, hourlyReset], warning: 80, critical: 95, warmedUp: true)
        expect(otherReset.pulse == nil, "5h reset does not rearm monthly alert")

        let noBoundary = AlertDecision.WindowInput(provider: .claude, visible: true,
            window: WindowUsage(usedPercent: 0.98, resetAt: nil, error: nil), windowKind: .monthly)
        let withoutReset = AlertDecision.evaluateCrossings(previous: [], inputs: [noBoundary], warning: 80, critical: 95, warmedUp: true)
        expect(withoutReset.pulse?.severity == .critical, "monthly threshold alerts without a fabricated reset")
        let lostReset = AlertDecision.evaluateCrossings(previous: first.next, inputs: [noBoundary], warning: 80, critical: 95, warmedUp: true)
        expect(lostReset.pulse == nil, "omitted reset metadata does not repeat a monthly alert")
        let restoredReset = AlertDecision.evaluateCrossings(previous: withoutReset.next, inputs: [monthly], warning: 80, critical: 95, warmedUp: true)
        expect(restoredReset.pulse == nil, "newly available reset metadata preserves an observed crossing")
        let nextPeriod = AlertDecision.WindowInput(provider: .claude, visible: true,
            window: WindowUsage(usedPercent: 0.98, resetAt: reset.addingTimeInterval(3600), error: nil), windowKind: .monthly)
        expect(AlertDecision.evaluateCrossings(previous: restoredReset.next, inputs: [nextPeriod], warning: 80, critical: 95, warmedUp: true).pulse != nil,
               "a changed provider reset boundary still identifies a new monthly period")
        let repeatedWithoutReset = AlertDecision.evaluateCrossings(previous: withoutReset.next, inputs: [noBoundary], warning: 80, critical: 95, warmedUp: true)
        expect(repeatedWithoutReset.pulse == nil, "boundaryless monthly alert fires once")
        let failedMonthly = AlertDecision.WindowInput(provider: .claude, visible: true, window: failure, windowKind: .monthly)
        let failureAfterCrossing = AlertDecision.evaluateCrossings(previous: withoutReset.next, inputs: [failedMonthly], warning: 80, critical: 95, warmedUp: true)
        expect(failureAfterCrossing.next == withoutReset.next, "failed monthly poll cannot rearm alerts")
        let lowMonthly = AlertDecision.WindowInput(provider: .claude, visible: true,
            window: WindowUsage(usedPercent: 0.1, resetAt: nil, error: nil), windowKind: .monthly)
        let observedReset = AlertDecision.evaluateCrossings(previous: withoutReset.next, inputs: [lowMonthly], warning: 80, critical: 95, warmedUp: true)
        expect(observedReset.next.isEmpty, "observed lower monthly usage rearms the next crossing")
        let nextCrossing = AlertDecision.evaluateCrossings(previous: observedReset.next, inputs: [noBoundary], warning: 80, critical: 95, warmedUp: true)
        expect(nextCrossing.pulse != nil, "next observed monthly threshold crossing can alert")
        expect(AlertDecision.evaluateCrossings(previous: [], inputs: [noBoundary], warning: 80, critical: 95, warmedUp: false).pulse == nil,
               "startup warmup still suppresses monthly pulses")

        let history = UsageHistoryStore.shared
        let key = "enterprise-test-\(UUID().uuidString)"
        history.record(key: key, window: unlimited, at: Date())
        expect(history.samples(key: key).isEmpty, "unlimited credits do not persist fake zero utilization")
        history.record(key: key, window: limited, at: Date())
        expect(history.samples(key: key).count == 1, "limited monthly utilization is recorded")
        history.record(provider: .claude, usage: original, at: Date().addingTimeInterval(-120))
        let seeded = UsageStore.seeded(.empty, provider: .claude, fillUnreported: true)
        expect(!seeded.monthly.hasReading, "percentage-only history cannot seed current monthly credit usage")
        expect(limited.amountCaption?.contains("0.47") == true, "credit caption preserves cent precision")
        expect(unlimited.amountCaption?.contains("unlimited") == true, "unlimited caption describes spend")
        if failures > 0 { exit(1) }
        print("PASS all Enterprise usage checks")
    }
}
