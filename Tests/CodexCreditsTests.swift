import Foundation

/// Codex `/wham/usage` reports purchased credits beside the rate limits.
/// Only accounts that hold credits get a summary line; the balance survives
/// a failed poll and is dropped by a parsed response that omits it.
@main
struct CodexCreditsTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    static func parse(_ json: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    }

    /// Shape of a funded Pro account response (values synthetic).
    static let fundedResponse = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 26,
          "limit_window_seconds": 604800,
          "reset_after_seconds": 588208,
          "reset_at": 1793999887
        },
        "secondary_window": null
      },
      "credits": {
        "has_credits": true,
        "unlimited": false,
        "overage_limit_reached": false,
        "balance": "1250.5000000000",
        "approx_local_messages": [310, 1620],
        "approx_cloud_messages": [50, 310]
      }
    }
    """

    static func main() {
        let funded = CodexCredits.parse(parse(fundedResponse)["credits"])
        expect(funded != nil, "funded account yields credits")
        expect(funded?.balance.map { abs($0 - 1250.5) < 0.0001 } == true, "balance parses from decimal string")
        expect(funded?.unlimited == false, "funded account is not unlimited")
        expect(funded?.localMessages == 310...1620, "local message range parses")
        expect(funded?.cloudMessages == 50...310, "cloud message range parses")

        let none = CodexCredits.parse(parse("""
        { "credits": { "has_credits": false, "unlimited": false } }
        """)["credits"])
        expect(none == nil, "has_credits false yields nothing")
        expect(CodexCredits.parse(nil) == nil, "missing credits block yields nothing")
        expect(CodexCredits.parse(parse("""
        { "credits": { "has_credits": true, "unlimited": false } }
        """)["credits"]) == nil, "has_credits without a balance yields nothing")

        let unlimited = CodexCredits.parse(parse("""
        { "credits": { "has_credits": true, "unlimited": true } }
        """)["credits"])
        expect(unlimited?.unlimited == true && unlimited?.balance == nil, "unlimited credits need no balance")

        let numeric = CodexCredits.parse(parse("""
        { "credits": { "has_credits": true, "unlimited": false, "balance": 12.5,
                       "approx_local_messages": [5], "approx_cloud_messages": [9, 3] } }
        """)["credits"])
        expect(numeric?.balance == 12.5, "numeric balance parses")
        expect(numeric?.localMessages == nil, "short range is rejected")
        expect(numeric?.cloudMessages == nil, "inverted range is rejected")

        let fractional = CodexCredits.parse(parse("""
        { "credits": { "has_credits": true, "unlimited": false, "balance": "5",
                       "approx_local_messages": [1.9, 2.1], "approx_cloud_messages": [-1, 4] } }
        """)["credits"])
        expect(fractional?.localMessages == nil, "fractional counts are rejected rather than truncated")
        expect(fractional?.cloudMessages == nil, "negative counts are rejected")

        let now = Date()
        let weekly = WindowUsage(usedPercent: 0.26, resetAt: now.addingTimeInterval(3600), error: nil)
        let prior = AppUsage(fiveHour: .unknown, weekly: weekly, plan: "pro",
                             reportedWindows: [.weekly], codexCredits: funded)
        let failed = AppUsage(fiveHour: WindowUsage(usedPercent: 0, resetAt: nil, error: "http 500"),
                              weekly: WindowUsage(usedPercent: 0, resetAt: nil, error: "http 500"))
        expect(AppUsage.merged(fetched: failed, retaining: prior, at: now).codexCredits == funded,
               "failed poll keeps the prior balance")
        let spent = AppUsage(fiveHour: .unknown, weekly: weekly, plan: "pro", reportedWindows: [.weekly])
        expect(AppUsage.merged(fetched: spent, retaining: prior, at: now).codexCredits == nil,
               "parsed response without credits clears the balance")
        let refreshed = CodexCredits(balance: 10, unlimited: false, localMessages: nil, cloudMessages: nil)
        let fresh = AppUsage(fiveHour: .unknown, weekly: weekly, plan: "pro",
                             reportedWindows: [.weekly], codexCredits: refreshed)
        expect(AppUsage.merged(fetched: fresh, retaining: prior, at: now).codexCredits == refreshed,
               "fresh balance replaces the prior one")

        if failures > 0 { print("FAILED \(failures) Codex credit checks"); exit(1) }
        print("PASS all Codex credit checks")
    }
}
