import Foundation

@main
struct ClaudeFableUsageTests {
    static var checks = 0

    static func expect(_ condition: Bool, _ label: String) {
        precondition(condition, label)
        checks += 1
        print("PASS \(label)")
    }

    static func parse(_ response: [String: Any]) -> AppUsage {
        let data = try! JSONSerialization.data(withJSONObject: response)
        let decoded = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return UsageFetcher.parseClaudeUsageResponse(decoded, plan: "max")
    }

    static func main() {
        var response: [String: Any] = [
            "five_hour": ["utilization": 10],
            "seven_day": ["utilization": 25],
            "limits": [["kind": "weekly_scoped", "percent": 63.5,
                        "resets_at": "2027-01-15T08:30:00Z",
                        "scope": ["model": ["display_name": "Fable"]]]]
        ]
        let usage = parse(response)
        expect(usage.visibleWindows == [.fiveHour, .weekly, .fableWeekly], "Fable appears alongside account-wide windows")
        expect(usage.fableWeekly.usedPercent == 0.635, "scoped percent uses percentage units")
        expect(usage.weekly.usedPercent == 0.25, "Fable does not replace the overall weekly quota")
        expect(usage.fableWeekly.resetAt == ISO8601DateFormatter().date(from: "2027-01-15T08:30:00Z"), "Fable retains its own reset boundary")
        expect(usage.peekWindowKind == .fiveHour, "adding Fable preserves the primary peek metric")
        expect(UsageWindow.fableWeekly.span == UsageWindow.weekly.span, "Fable has a weekly history lifetime")

        for (name, percent) in [("Fable", 0.0), ("Fable 5.1", 0.5), ("fable", 100.0)] {
            response["limits"] = [["kind": "weekly_scoped", "percent": percent,
                                   "scope": ["model": ["display_name": name]]]]
            let result = parse(response)
            expect(result.visibleWindows.contains(.fableWeekly) && result.fableWeekly.usedPercent == percent / 100,
                   "\(name) keeps its genuine \(percent)% reading")
        }
        for entry: [String: Any] in [
            ["kind": "weekly_all", "percent": 90, "scope": ["model": ["display_name": "Fable"]]],
            ["kind": "weekly_scoped", "percent": 90, "scope": ["model": ["display_name": "Opus"]]],
            ["kind": "weekly_scoped", "percent": NSNull(), "scope": ["model": ["display_name": "Fable"]]],
            ["kind": "weekly_scoped", "scope": ["model": ["display_name": "Fable"]]],
            ["kind": "weekly_scoped", "percent": "unknown", "scope": ["model": ["display_name": "Fable"]]]
        ] {
            response["limits"] = [entry]
            expect(!parse(response).visibleWindows.contains(.fableWeekly), "unrelated or incomplete scoped limit is omitted")
        }
        response.removeValue(forKey: "limits")
        expect(parse(response).visibleWindows == [.fiveHour, .weekly], "Max plan alone never creates a Fable quota")
        response["seven_day_overage_included"] = ["utilization": 42, "resets_at": 1_800_000_000]
        expect(parse(response).fableWeekly.usedPercent == 0.42, "legacy Fable window remains supported")
        response["limits"] = [["kind": "weekly_scoped", "percent": 15,
                               "scope": ["model": ["display_name": "Fable"]]]]
        expect(parse(response).fableWeekly.usedPercent == 0.15, "scoped reading wins over duplicate legacy window")

        let failure = WindowUsage(usedPercent: 0, resetAt: nil, error: "HTTP 500")
        let failed = AppUsage(fiveHour: failure, weekly: failure, monthly: failure, fableWeekly: failure)
        let beforeReset = Date(timeIntervalSince1970: 1_790_000_000)
        let retained = AppUsage.merged(fetched: failed, retaining: usage, at: beforeReset)
        expect(retained.fableWeekly.usedPercent == 0.635 && retained.fableWeekly.error == "HTTP 500", "failed refresh retains Fable reading and error")
        expect(retained.visibleWindows == usage.visibleWindows, "failed refresh retains discovered windows")
        let expired = AppUsage.merged(fetched: failed, retaining: usage, at: Date(timeIntervalSince1970: 1_900_000_000))
        expect(!expired.fableWeekly.hasReading, "Fable reading expires at its own reset")
        expect(failed.visibleWindows == [.fiveHour, .weekly], "cold failure never invents a Fable quota")
        let removed = AppUsage.merged(fetched: parse([:]), retaining: usage, at: beforeReset)
        expect(!removed.visibleWindows.contains(.fableWeekly) && removed.fableWeekly.isUnreported, "successful omission removes previous Fable reading")
        let onlyFable = parse(["limits": [["kind": "weekly_scoped", "percent": 30,
                                         "scope": ["model": ["display_name": "Fable"]]]]])
        expect(onlyFable.peekWindowKind == .fableWeekly && onlyFable.peekWindowIsWeekly, "Fable-only fallback preserves weekly identity")
        print("\(checks) Fable checks passed")
    }
}
