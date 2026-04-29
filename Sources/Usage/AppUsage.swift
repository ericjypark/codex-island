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

    static let empty = AppUsage(fiveHour: .unknown, weekly: .unknown)
}
