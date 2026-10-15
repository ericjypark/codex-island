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
        expect(weeklyFallback.peekWindowKind(preferring: .fiveHour) == .weekly, "unavailable 5h reading still falls back to real weekly reading")
        let enterprise = AppUsage(fiveHour: limited, weekly: limited, monthly: limited,
            reportedWindows: [.fiveHour, .weekly, .monthly])
        expect(enterprise.peekWindowKind(preferring: .weekly) == .weekly,
               "weekly preference applies alongside Enterprise monthly credits")
        let response = try! JSONSerialization.jsonObject(with: Data(#"{"extra_usage":{"is_enabled":true,"used_credits":47,"monthly_limit":1600}}"#.utf8)) as! [String: Any]
        let noPlan = UsageFetcher.parseClaudeUsageResponse(response, plan: nil)
        expect(noPlan.visibleWindows == [.monthly] && noPlan.monthly.usedAmount == 0.47,
               "enabled credits survive missing optional plan metadata")
        expect(UsageFetcher.parseClaudeUsageResponse(response, plan: "max").monthly.hasReading,
               "response schema determines available credits")
        let reset = Date().addingTimeInterval(3600)
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
        let summary = UsageCreditsSummary(window: limited, color: .white, mode: .used)
        expect(summary.reading.value == Double(DisplayNumber.percent(limited.usedPercent * 100)),
               "Credits summary uses measured utilization")
        expect(summary.amountText?.contains("0.47") == true && summary.amountText?.contains("16.00") == true,
               "Credits summary keeps exact spent amount and cap")
        let remainingSummary = UsageCreditsSummary(window: limited, color: .white, mode: .remaining)
        expect(remainingSummary.reading.value == Double(DisplayNumber.percent((1 - limited.usedPercent) * 100)),
               "Credits summary respects remaining mode")
        expect(remainingSummary.amountText == summary.amountText,
               "Remaining mode never relabels actual spend as remaining money")
        expect(UsageCreditsSummary(window: zero, color: .white, mode: .used).reading.value == 0,
               "Credits summary retains genuine zero")
        for mode in UsageDisplayMode.allCases {
            let absent = UsageCreditsSummary(window: .unknown, color: .white, mode: mode)
            expect(absent.reading.value == nil && absent.reading.amount == nil,
                   "Missing Credits has no fabricated percentage in \(mode)")
            expect(!absent.statusText.isEmpty, "Missing Credits explains its absent reading")
            let noLimit = UsageCreditsSummary(window: unlimited, color: .white, mode: mode)
            expect(noLimit.reading.value == nil && noLimit.reading.amount != nil,
                   "Unlimited Credits has spend but no percentage in \(mode)")
        }
        let creditFailure = UsageCreditsSummary(window: retained.monthly, color: .white, mode: .used)
        expect(creditFailure.statusText.contains("HTTP 500") && creditFailure.amountText?.contains("0.47") == true,
               "Credits summary preserves carried amounts and fetch errors separately")
        let noHistory = UsageCreditsSummary(window: failure, color: .white, mode: .remaining)
        expect(noHistory.reading.value == nil && noHistory.statusText == "HTTP 500",
               "Failed first Credits fetch is not 100 percent remaining")
        expect(!UsageCreditsSummary(window: epoch, color: .white, mode: .used).statusText.isEmpty,
               "Credits summary retains reset information")
        let overCap = WindowUsage(usedPercent: 1.2, resetAt: nil, error: nil, usedAmount: 24, limitAmount: 20)
        expect(UsageCreditsSummary(window: overCap, color: .white, mode: .used).reading.value == 100,
               "Over-cap Credits bar stays within its available width")
        expect(UsageCreditsSummary(window: overCap, color: .white, mode: .remaining).reading.value == 0,
               "Over-cap Credits has no remaining quota")
        expect(UsageCreditsSummary(window: closed, color: .white, mode: .used).reading.value == 100
               && UsageCreditsSummary(window: closed, color: .white, mode: .remaining).reading.value == 0,
               "Zero-limit Credits stays exhausted in both display modes")
        for kind in [UsageWindow.fiveHour, .weekly] {
            func input(_ fraction: Double, reset: Date? = nil) -> AlertDecision.WindowInput {
                AlertDecision.WindowInput(provider: .muse, visible: true,
                    window: WindowUsage(usedPercent: fraction, resetAt: reset, error: nil), windowKind: kind)
            }
            func evaluate(_ previous: Set<AlertEngine.CrossingKey>, _ value: AlertDecision.WindowInput,
                          warmedUp: Bool = true) -> AlertDecision.CrossingsEvalResult {
                AlertDecision.evaluateCrossings(previous: previous, inputs: [value],
                    warning: 80, critical: 95, warmedUp: warmedUp)
            }
            let first = evaluate([], input(0.85))
            expect(first.pulse?.severity == .warning, "Muse \(kind) crossing alerts without reset metadata")
            expect(evaluate(first.next, input(0.85)).pulse == nil,
                   "Muse \(kind) repeated resetless readings do not pulse again")
            expect(evaluate([], input(0.85), warmedUp: false).pulse == nil,
                   "Muse \(kind) startup warmup remains silent")
            let failedInput = AlertDecision.WindowInput(provider: .muse, visible: true,
                                                        window: .unknown, windowKind: kind)
            let afterFailure = evaluate(first.next, failedInput)
            expect(afterFailure.next == first.next && afterFailure.pulse == nil,
                   "Muse \(kind) missing reading cannot rearm an alert")
            let rearmed = evaluate(first.next, input(0.20))
            expect(rearmed.next.isEmpty && evaluate(rearmed.next, input(0.85)).pulse != nil,
                   "Muse \(kind) observed usage drop rearms the next crossing")
            let boundary = Date(timeIntervalSince1970: 1_800_000_000)
            let restored = evaluate(first.next, input(0.85, reset: boundary))
            expect(restored.pulse == nil && restored.next.allSatisfy { $0.resetAt == boundary },
                   "Muse \(kind) arriving reset metadata preserves crossing memory")
            expect(evaluate(restored.next, input(0.85)).pulse == nil,
                   "Muse \(kind) lost reset metadata cannot duplicate a pulse")
            expect(evaluate(restored.next, input(0.85, reset: boundary.addingTimeInterval(3600))).pulse != nil,
                   "Muse \(kind) new provider boundary allows a new alert")
            let critical = evaluate(first.next, input(0.97))
            expect(critical.pulse?.severity == .critical && critical.next.count == 2,
                   "Muse \(kind) critical crossing alerts independently")
            let otherKind: UsageWindow = kind == .weekly ? .fiveHour : .weekly
            let switched = AlertDecision.WindowInput(provider: .muse, visible: true,
                window: WindowUsage(usedPercent: 0.85, resetAt: nil, error: nil), windowKind: otherKind)
            expect(evaluate(first.next, switched).pulse != nil,
                   "Muse session and weekly crossings retain separate identities")
        }
        let museUnknown = AlertDecision.WindowInput(provider: .muse, visible: true, window: .unknown)
        let startupGap = AlertDecision.evaluateCrossings(previous: [], inputs: [museUnknown],
            warning: 80, critical: 95, warmedUp: true, warmingProviders: [.muse])
        expect(startupGap.next.isEmpty && startupGap.pulse == nil,
               "Legacy refresh completion cannot establish an unknown Muse baseline")
        let museInitial = AlertDecision.WindowInput(provider: .muse, visible: true,
            window: WindowUsage(usedPercent: 0.85, resetAt: nil, error: nil))
        let codexCrossing = AlertDecision.WindowInput(provider: .codex, visible: true,
            window: WindowUsage(usedPercent: 0.85, resetAt: Date(timeIntervalSince1970: 1_800_000_000), error: nil))
        let firstMuseSnapshot = AlertDecision.evaluateCrossings(previous: startupGap.next,
            inputs: [museInitial, codexCrossing], warning: 80, critical: 95,
            warmedUp: true, warmingProviders: [.muse])
        expect(firstMuseSnapshot.next.contains { $0.provider == .muse },
               "Delayed first Muse snapshot seeds crossing memory")
        expect(firstMuseSnapshot.pulse?.lines.map(\.provider) == [.codex],
               "Muse startup is silent without suppressing another provider's crossing")
        let museRepeated = AlertDecision.evaluateCrossings(previous: firstMuseSnapshot.next,
            inputs: [museInitial, codexCrossing], warning: 80, critical: 95, warmedUp: true)
        expect(museRepeated.pulse == nil, "Muse initial threshold remains deduplicated after warmup")
        let museLater = AlertDecision.WindowInput(provider: .muse, visible: true,
            window: WindowUsage(usedPercent: 0.97, resetAt: nil, error: nil))
        let laterCrossing = AlertDecision.evaluateCrossings(previous: museRepeated.next,
            inputs: [museLater], warning: 80, critical: 95, warmedUp: true)
        expect(laterCrossing.pulse?.severity == .critical,
               "A real Muse crossing after its baseline still alerts")
        if failures > 0 { exit(1) }
        print("PASS all Enterprise usage checks")
    }
}
