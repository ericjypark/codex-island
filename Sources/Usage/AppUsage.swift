import Foundation

/// Usage periods reported by providers. Named beside AppUsage so the pure
/// value layer can retain rate windows and monthly credit periods together.
enum UsageWindow: String, Codable {
    case fiveHour
    case weekly
    case monthly

    /// How long the window runs before the provider resets it. Bounds how
    /// long a recorded reading stays meaningful once polling stops working.
    var span: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .weekly:   return 7 * 86400
        case .monthly:  return 31 * 86400
        }
    }
}

/// One quota window or credit period. usedPercent is normalized to 0...1
/// regardless of what the upstream API returns.
struct WindowUsage {
    let usedPercent: Double
    let resetAt: Date?
    let error: String?
    let usedAmount: Double?
    let limitAmount: Double?
    let currencyCode: String?

    init(usedPercent: Double, resetAt: Date?, error: String?,
         usedAmount: Double? = nil, limitAmount: Double? = nil, currencyCode: String? = nil) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.error = error
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.currencyCode = currencyCode
    }

    static let unknown = WindowUsage(usedPercent: 0, resetAt: nil, error: "no data")

    /// True when `usedPercent` is a measurement rather than a struct default.
    ///
    /// A failed fetch produces `usedPercent: 0` alongside an error
    /// (`UsageFetcher.errorPair`), so a bare zero is ambiguous: it reads
    /// identically to a genuinely empty window. Rendering it anyway shows a
    /// confident `0%` — or, in `remaining` mode, a full `100%` ring — for a
    /// window we know nothing about. Every consumer that displays or alerts
    /// on a percentage must gate on this first.
    ///
    /// An error alongside a *non-zero* percentage is the carry-forward shape
    /// from `AppUsage.merged`: a real prior reading with a fresh failure
    /// attached. That still counts as a reading.
    var hasReading: Bool { !(error != nil && usedPercent == 0 && usedAmount == nil) }

    var hasPercentageReading: Bool { hasReading && !(usedAmount != nil && limitAmount == nil) }
    var isUnlimitedAmount: Bool { usedAmount != nil && limitAmount == nil }

    /// True for the passive sentinel a successfully parsed response leaves on
    /// a window it doesn't include (`WindowUsage.unknown`) — the provider
    /// affirmatively not offering the window, as opposed to a fetch failure,
    /// whose error carries the failure message. `merged` treats the two
    /// differently: a failure preserves the prior reading; an unreported
    /// window displaces it. A history seed also wears the "no data" caption
    /// but with a real percentage, so it stays a reading, not this.
    var isUnreported: Bool { !hasReading && error == WindowUsage.unknown.error }

    var percentInt: Int { Int((usedPercent * 100).rounded()) }

    func displayedFraction(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .used:
            return usedPercent
        case .remaining:
            return max(0, 1 - usedPercent)
        }
    }

    func displayedPercentInt(mode: UsageDisplayMode) -> Int {
        Int((displayedFraction(mode: mode) * 100).rounded())
    }
}

struct AppUsage {
    var fiveHour: WindowUsage
    var weekly: WindowUsage
    var monthly: WindowUsage
    /// Provider-reported plan tier — Claude's `subscriptionType` (free/pro/max/enterprise)
    /// or Codex's `plan_type` (free/plus/pro). nil when unknown.
    var plan: String?

    // nil means no successful window discovery yet, not a two-window plan.
    var reportedWindows: [UsageWindow]?

    init(fiveHour: WindowUsage, weekly: WindowUsage, monthly: WindowUsage = .unknown,
         plan: String? = nil,
         reportedWindows: [UsageWindow]? = nil) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.monthly = monthly
        self.plan = plan
        self.reportedWindows = reportedWindows
    }

    static let empty = AppUsage(fiveHour: .unknown, weekly: .unknown)

    var visibleWindows: [UsageWindow] {
        let order: [UsageWindow] = [.fiveHour, .weekly, .monthly]
        if let reportedWindows { return order.filter { reportedWindows.contains($0) } }
        return order.filter { !window($0).isUnreported }
    }

    func window(_ kind: UsageWindow) -> WindowUsage {
        switch kind {
        case .fiveHour: return fiveHour
        case .weekly: return weekly
        case .monthly: return monthly
        }
    }

    var peekWindow: WindowUsage { window(peekWindowKind) }

    var peekWindowKind: UsageWindow {
        if visibleWindows.contains(.fiveHour) { return .fiveHour }
        if visibleWindows.contains(.weekly) { return .weekly }
        if visibleWindows.contains(.monthly) { return .monthly }
        return .fiveHour
    }

    /// Which window `peekWindow` selected — the peek chrome (VoiceOver label,
    /// window-length fallback glyph) must describe the same window it shows.
    var peekWindowIsWeekly: Bool {
        peekWindowKind == .weekly
    }

    /// Fold a fetch result into the values currently on screen.
    ///
    /// Per window: a fresh reading wins outright. A failed window keeps the
    /// prior reading and takes the new error, so the panel shows the last
    /// true number captioned with what went wrong, instead of either blanking
    /// to a fabricated 0% or hiding the failure entirely. The carried reading
    /// is released once its own reset time has passed — past that boundary the
    /// percentage describes a window that no longer exists, and a confident
    /// stale number is worse than an honest "—".
    ///
    /// Callers that must NOT carry forward (a terminal auth failure, where the
    /// token can never refresh those numbers again) skip this and assign the
    /// fetched value directly — see `UsageStore.refresh`.
    static func merged(fetched: AppUsage, retaining prior: AppUsage, at now: Date) -> AppUsage {
        AppUsage(
            fiveHour: carryForward(fetched.fiveHour, prior: prior.fiveHour, at: now),
            weekly: carryForward(fetched.weekly, prior: prior.weekly, at: now),
            monthly: carryForward(fetched.monthly, prior: prior.monthly, at: now),
            // Plan tier is read from the credential store, not the usage
            // response, so a failed fetch shouldn't blank the chip's badge.
            plan: fetched.plan ?? prior.plan,
            reportedWindows: fetched.reportedWindows ?? prior.reportedWindows
        )
    }

    private static func carryForward(
        _ fetched: WindowUsage, prior: WindowUsage, at now: Date
    ) -> WindowUsage {
        guard !fetched.hasReading, prior.hasReading else { return fetched }
        // A parsed response that omits the window is the provider saying the
        // plan doesn't have one (single-window Codex plans, mid-2026) —
        // displace the prior reading rather than papering over it. Carrying
        // here froze a mislabeled history seed forever: seeds have no
        // resetAt, so the release below could never fire.
        if fetched.isUnreported { return fetched }
        if let reset = prior.resetAt, reset <= now { return fetched }
        return WindowUsage(
            usedPercent: prior.usedPercent, resetAt: prior.resetAt, error: fetched.error,
            usedAmount: prior.usedAmount, limitAmount: prior.limitAmount,
            currencyCode: prior.currencyCode
        )
    }

    /// Placeholder values shown when a provider is toggled off. Non-zero
    /// so the chart vocabulary stays visible (a 0% ring reads as broken,
    /// a 45% ring reads as "data we're choosing not to surface").
    static let dummy = AppUsage(
        fiveHour: WindowUsage(usedPercent: 0.45, resetAt: nil, error: nil),
        weekly: WindowUsage(usedPercent: 0.28, resetAt: nil, error: nil)
    )
}
