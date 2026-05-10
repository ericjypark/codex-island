import Foundation
import Combine

/// Drives the approaching-limit alert state. Subscribes to `UsageStore`
/// publishers + the alert/visibility preference stores, derives a current
/// severity, and emits one-shot `pulseEvent`s when a tracked 5-hour window
/// first crosses a threshold inside its current reset cycle.
///
/// The pure-function helpers (`computeSeverity`, `evaluateCrossings`) are
/// intentionally factored out so they remain unit-testable later if/when
/// the project gains a test target — today there isn't one (the build is
/// `swiftc` over `Sources/**/*.swift`, no SwiftPM, no XCTest).
@MainActor
final class AlertEngine: ObservableObject {
    static let shared = AlertEngine()

    // MARK: - Public state

    enum Severity: Int, Comparable {
        case none = 0, warning = 1, critical = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    enum Provider: String, Hashable {
        case claude
        case codex
        case gemini
    }

    enum Threshold: Int, Hashable {
        case warning, critical
    }

    struct PulseLine: Hashable {
        let provider: Provider
        let percent: Int
        let resetAt: Date?
    }

    struct PulseEvent: Identifiable, Equatable {
        let id = UUID()
        let severity: Severity
        let lines: [PulseLine]
    }

    /// Highest severity across visible 5h windows currently at/above their
    /// respective threshold. Drives the silhouette glow color.
    @Published private(set) var severity: Severity = .none

    /// One-shot pulse event. UI sets back to `nil` after consuming.
    @Published var pulseEvent: PulseEvent?

    /// Per-side severity for the peek pill content swap. Read by the pill.
    @Published private(set) var claudeSeverity: Severity = .none
    @Published private(set) var codexSeverity: Severity = .none
    @Published private(set) var geminiSeverity: Severity = .none

    // MARK: - Internal state

    struct CrossingKey: Hashable {
        let provider: Provider
        let threshold: Threshold
        let resetAt: Date
    }

    private var crossings: Set<CrossingKey> = []
    private var warmedUp = false
    private var subs: Set<AnyCancellable> = []

    private init() {}

    // MARK: - Wiring

    func start() {
        // Re-evaluate on every relevant publisher tick. We re-derive the
        // full state from current store values rather than pattern-match
        // on which publisher fired — simpler, and the UsageStore refresh
        // cadence is on the order of minutes so the cost is negligible.
        let triggers: [AnyPublisher<Void, Never>] = [
            UsageStore.shared.$claude.map { _ in () }.eraseToAnyPublisher(),
            UsageStore.shared.$codex.map { _ in () }.eraseToAnyPublisher(),
            AlertThresholdStore.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            ProviderVisibilityStore.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(triggers)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                Task { @MainActor in self?.recompute() }
            }
            .store(in: &subs)

        // Run once at startup so initial severity reflects current usage.
        recompute()
    }

    // MARK: - Recompute

    private func recompute() {
        let store = AlertThresholdStore.shared
        let visibility = ProviderVisibilityStore.shared
        let usage = UsageStore.shared

        let enabled = store.enabled
        let warning = store.warningPercent
        let critical = store.criticalPercent
        let validThresholds = warning < critical
            && AlertThresholdStore.warningRange.contains(warning)
            && AlertThresholdStore.criticalRange.contains(critical)

        let inputs: [WindowInput] = [
            WindowInput(
                provider: .claude,
                visible: visibility.claudeVisible,
                window: usage.claude.fiveHour
            ),
            WindowInput(
                provider: .codex,
                visible: visibility.codexVisible,
                window: usage.codex.fiveHour
            ),
            WindowInput(
                provider: .gemini,
                visible: visibility.geminiVisible,
                window: usage.gemini.fiveHour
            ),
        ]

        // Severity drives the silhouette tint and is always computed: a
        // user launching at 96% should see red immediately, even before
        // crossing memory has formed.
        let perWindowSeverity: [Provider: Severity] = enabled && validThresholds
            ? Self.computeSeverity(
                inputs: inputs,
                warning: warning,
                critical: critical
            )
            : [:]

        let claudeSev = perWindowSeverity[.claude] ?? .none
        let codexSev = perWindowSeverity[.codex] ?? .none
        let geminiSev = perWindowSeverity[.gemini] ?? .none
        let combined = max(claudeSev, max(codexSev, geminiSev))

        if claudeSev != self.claudeSeverity { self.claudeSeverity = claudeSev }
        if codexSev != self.codexSeverity { self.codexSeverity = codexSev }
        if geminiSev != self.geminiSeverity { self.geminiSeverity = geminiSev }
        if combined != self.severity { self.severity = combined }

        guard enabled, validThresholds else {
            // Re-enabling later should warmup again, not retroactively pulse
            // for windows that were already above threshold while disabled.
            crossings.removeAll()
            warmedUp = false
            return
        }

        // Gate crossing memory + pulses on real data flow. The synchronous
        // startup recompute and any subscription-init emissions that arrive
        // before the first network fetch (or test injection) lands have
        // `lastUpdated == nil` and skip the crossing path entirely. The
        // first recompute that sees `lastUpdated != nil` consumes warmup.
        guard usage.lastUpdated != nil else { return }

        let result = Self.evaluateCrossings(
            previous: crossings,
            inputs: inputs,
            warning: warning,
            critical: critical,
            warmedUp: warmedUp
        )
        crossings = result.next
        if !warmedUp {
            warmedUp = true
            return
        }

        guard let pulse = result.pulse else { return }
        if isPulseSuppressed() { return }
        // Always replace, even if a previous pulse hadn't been consumed —
        // the new one carries strictly more current information.
        pulseEvent = pulse
    }

    /// Resets crossing memory and forces post-warmup state so the next
    /// usage update (e.g. a test injection from the Settings UI) fires a
    /// pulse rather than being eaten by warmup. Strictly a developer
    /// affordance — production code paths don't call this.
    func prepareForPreview() {
        crossings.removeAll()
        warmedUp = true
    }

    private func isPulseSuppressed() -> Bool {
        if AppEnvironment.isDemo {
            return true
        }
        // Panel-expanded suppression: we don't have a direct handle to the
        // active IslandModel from here. The view layer is responsible for
        // dropping `pulseEvent` when state == .expanded; we still publish.
        // This keeps the engine free of view-state coupling.
        return false
    }

    // MARK: - Pure helpers (unit-testable)

    struct WindowInput {
        let provider: Provider
        let visible: Bool
        let window: WindowUsage
    }

    /// Returns severity per visible window whose percent meets at least the
    /// warning threshold. Hidden providers and `.error`-only windows yield
    /// no entry.
    static func computeSeverity(
        inputs: [WindowInput],
        warning: Int,
        critical: Int
    ) -> [Provider: Severity] {
        var out: [Provider: Severity] = [:]
        for input in inputs {
            guard input.visible else { continue }
            // Treat error-only states (no value, error set) as "no signal".
            if input.window.error != nil && input.window.usedPercent == 0 {
                continue
            }
            let pct = input.window.percentInt
            if pct >= critical {
                out[input.provider] = .critical
            } else if pct >= warning {
                out[input.provider] = .warning
            }
        }
        return out
    }

    struct CrossingsEvalResult {
        let next: Set<CrossingKey>
        /// Non-nil when at least one new crossing was recorded AND we're
        /// past warmup. `nil` during warmup or when nothing crossed.
        let pulse: PulseEvent?
    }

    /// Pure-function crossing evaluator.
    /// - Prunes keys whose `resetAt` no longer matches the current window's
    ///   reset (window reset → forget previous crossings).
    /// - Adds keys for any (provider, threshold) combo that newly meets
    ///   the threshold inside the current reset cycle.
    /// - Returns a `PulseEvent` describing newly added keys (one event per
    ///   tick, possibly covering multiple providers/thresholds), unless we
    ///   haven't completed warmup yet.
    static func evaluateCrossings(
        previous: Set<CrossingKey>,
        inputs: [WindowInput],
        warning: Int,
        critical: Int,
        warmedUp: Bool
    ) -> CrossingsEvalResult {
        var next = previous

        // Prune keys whose resetAt is stale relative to the current window.
        // A `nil` resetAt means we have no current boundary; in that case
        // we can't evaluate crossings for that provider, so leave its keys
        // alone (they'll get pruned once a real resetAt arrives).
        for input in inputs {
            guard let currentReset = input.window.resetAt else { continue }
            next = next.filter { key in
                key.provider != input.provider || key.resetAt == currentReset
            }
        }

        var newCrossings: [CrossingKey] = []
        var pulseLines: [PulseLine] = []
        var maxSeverity: Severity = .none

        for input in inputs {
            guard input.visible else { continue }
            guard let resetAt = input.window.resetAt else { continue }
            if input.window.error != nil && input.window.usedPercent == 0 {
                continue
            }
            let pct = input.window.percentInt

            for threshold in [Threshold.warning, Threshold.critical] {
                let bound = (threshold == .warning) ? warning : critical
                guard pct >= bound else { continue }
                let key = CrossingKey(
                    provider: input.provider,
                    threshold: threshold,
                    resetAt: resetAt
                )
                if !next.contains(key) {
                    next.insert(key)
                    newCrossings.append(key)
                }
            }

            // Build pulse line per provider that crossed any threshold this
            // tick — coalesces both providers into a single event when both
            // happen on the same usage update.
            if newCrossings.contains(where: { $0.provider == input.provider }) {
                let sev: Severity = pct >= critical
                    ? .critical
                    : (pct >= warning ? .warning : .none)
                if sev != .none {
                    maxSeverity = max(maxSeverity, sev)
                    pulseLines.append(PulseLine(
                        provider: input.provider,
                        percent: pct,
                        resetAt: resetAt
                    ))
                }
            }
        }

        let pulse: PulseEvent? = {
            guard warmedUp, !pulseLines.isEmpty else { return nil }
            return PulseEvent(severity: maxSeverity, lines: pulseLines)
        }()
        return CrossingsEvalResult(next: next, pulse: pulse)
    }
}

