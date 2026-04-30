import Foundation

/// One rate-limit window (e.g. Claude's 5h, Codex's 7d). usedPercent is
/// normalized to 0...1 regardless of what the upstream API returns.
struct WindowUsage {
    let usedPercent: Double
    let resetAt: Date?
    let error: String?

    static let unknown = WindowUsage(usedPercent: 0, resetAt: nil, error: "no data")
}

struct AppUsage {
    var fiveHour: WindowUsage
    var weekly: WindowUsage
    /// Provider-reported plan tier — Claude's `subscriptionType` (free/pro/max)
    /// or Codex's `plan_type` (free/plus/pro). nil when unknown.
    var plan: String?

    init(fiveHour: WindowUsage, weekly: WindowUsage, plan: String? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.plan = plan
    }

    static let empty = AppUsage(fiveHour: .unknown, weekly: .unknown)

    /// Placeholder values shown when a provider is toggled off. Non-zero
    /// so the chart vocabulary stays visible (a 0% ring reads as broken,
    /// a 45% ring reads as "data we're choosing not to surface").
    static let dummy = AppUsage(
        fiveHour: WindowUsage(usedPercent: 0.45, resetAt: nil, error: nil),
        weekly: WindowUsage(usedPercent: 0.28, resetAt: nil, error: nil)
    )
}
