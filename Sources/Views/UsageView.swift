import SwiftUI
import AppKit

/// Usage data row. The chrome (provider titles, footer chip + page dots +
/// sync status) lives in `PanelHeader` / `PanelFooter` so it stays fixed
/// while this row swipes between usage and cost screens.
///
/// Branches on `(claudeOn, codexOn)` from `ProviderVisibilityStore`:
///   - both on:  two `ChartsBlock`s with a hairline divider (default).
///   - one on:   the live block on its native side, hairline, then a
///               per-model token breakdown filling the freed half.
///   - both off: a centered `BothHiddenPlaceholder`.
struct UsageView: View {
    @ObservedObject private var store = UsageStore.shared
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    private var style: ChartStyle { pref.style }

    var body: some View {
        let claudeOn = visibility.claudeVisible
        let codexOn = visibility.codexVisible

        HStack(spacing: 0) {
            switch (claudeOn, codexOn) {
            case (true, true):
                ChartsBlock(color: IslandColor.claude, usage: store.claude,
                            style: style, seed: 1, provider: .claude)
                hairline
                ChartsBlock(color: IslandColor.codex, usage: store.codex,
                            style: style, seed: 3, provider: .codex)
            case (true, false):
                ChartsBlock(color: IslandColor.claude, usage: store.claude,
                            style: style, seed: 1, provider: .claude)
                hairline
                PerModelBreakdown(provider: .claude, metric: .tokens)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                    .transition(breakdownTransition)
            case (false, true):
                PerModelBreakdown(provider: .codex, metric: .tokens)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 12)
                    .transition(breakdownTransition)
                hairline
                ChartsBlock(color: IslandColor.codex, usage: store.codex,
                            style: style, seed: 3, provider: .codex)
            case (false, false):
                BothHiddenPlaceholder()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// Slight scale + opacity gives the breakdown half a sense of "expanding
    /// into the freed space" rather than a hard crossfade. Same curve the
    /// chart-style swap uses; reads as a single morph paired with the
    /// `withAnimation(.openMorph)` on the Settings toggle.
    private var breakdownTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97))
    }

    private var hairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.clear, .white.opacity(0.06), .clear],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}

struct ChartsBlock: View {
    let color: Color
    let usage: AppUsage
    let style: ChartStyle
    let seed: Int
    let provider: AlertEngine.Provider

    /// Treat the block as needing re-auth when both windows are stuck on the
    /// scope-insufficient sentinel. Either tile alone could be a transient
    /// per-window failure, but matching pair = the underlying token genuinely
    /// lacks the required scope.
    private var needsReauth: Bool {
        usage.fiveHour.error == ClaudeCredentials.reauthRequiredMessage
            && usage.weekly.error == ClaudeCredentials.reauthRequiredMessage
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 18) {
                ChartTile(style: style, color: color, labelKey: "5h",
                          window: usage.fiveHour, seed: seed,
                          provider: provider, windowKind: .fiveHour)
                ChartTile(style: style, color: color, labelKey: "week",
                          window: usage.weekly, seed: seed + 1,
                          provider: provider, windowKind: .weekly)
            }
            if needsReauth && ClaudeCredentials.canPromptReauth() {
                ReauthButton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

/// Inline action shown below the Claude tiles when the keychain token is
/// missing the scope the usage endpoint now requires. Spawns
/// `claude auth login` and polls for the keychain to update — the chip
/// recovers on its own when the new scoped token lands.
struct ReauthButton: View {
    @ObservedObject private var store = UsageStore.shared
    @State private var hovered = false

    var body: some View {
        Button {
            store.reauthenticateClaude()
        } label: {
            Text(store.claudeReauthInProgress ? L10n.tr("waiting for browser…") : L10n.tr("Re-authenticate"))
                .font(Typography.label)
                .foregroundStyle(.white.opacity(hovered && !store.claudeReauthInProgress ? 0.95 : 0.72))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(hovered && !store.claudeReauthInProgress ? 0.08 : 0.04))
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(store.claudeReauthInProgress)
        .onHover { hovered = $0 }
    }
}

struct ChartTile: View {
    let style: ChartStyle
    let color: Color
    let labelKey: String
    let window: WindowUsage
    let seed: Int
    let provider: AlertEngine.Provider
    let windowKind: UsageWindow
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared
    @ObservedObject private var historyStore = UsageHistoryStore.shared

    /// Locked tile height across all 5 styles so the panel size is
    /// identical regardless of what the user picks.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        let value = window.displayedFraction(mode: usageDisplay.mode) * 100   // 0-100
        let sub = subCaption()
        let label = L10n.tr(labelKey)

        Group {
            switch style {
            case .ring:    RingChart(value: value, color: color, label: label, sub: sub)
            case .bar:     BarChart(value: value, color: color, label: label, sub: sub)
            case .stepped: SteppedChart(value: value, color: color, label: label, sub: sub)
            case .numeric: NumericChart(value: value, color: color, label: label, sub: compactSubCaption())
            case .spark:   SparkChart(value: value, color: color, label: label, sub: sub,
                                      seed: seed, history: historyPoints())
            }
        }
        .id(style)
        // Blur + scale + opacity, all on the same strong ease-out at 220ms.
        // The blur masks the geometric mismatch between Ring and Bar so the
        // crossfade reads as one morph instead of two stacked objects.
        .transition(.chartSwap.animation(.chartSwap))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("%@, %d%%", label, Int(value)))
        .accessibilityValue(subCaption())
    }

    /// Recorded readings for this window, mapped through the active
    /// used/remaining mode into display percent (0-100), oldest first — the
    /// same transform `value` uses, so the history and the live point agree.
    private func historyPoints() -> [Double] {
        let mode = usageDisplay.mode
        return historyStore.samples(provider: provider, window: windowKind).map { sample in
            WindowUsage(usedPercent: sample.used, resetAt: nil, error: nil)
                .displayedFraction(mode: mode) * 100
        }
    }

    private func subCaption() -> String {
        if let r = window.resetAt {
            let delta = max(0, r.timeIntervalSinceNow)
            return L10n.tr("resets in %@", Duration.compact(delta))
        }
        // "no data" is our internal sentinel for "API returned null for this
        // window" — most commonly a brand-new 5h period before the first
        // OAuth call lands. Hide it so the tile reads as a passive
        // window-context cue (the "5h"/"week" header label communicates the
        // window type) instead of looking broken. Real errors still surface.
        if let err = window.error, err != "no data" {
            // Suppress the scope-insufficient text when the inline re-auth
            // button is going to appear below the tiles — otherwise the same
            // remediation hint reads twice (caption + button label). Users
            // without a discoverable `claude` binary still get the raw text
            // so they know the manual fix.
            if err == ClaudeCredentials.reauthRequiredMessage,
               ClaudeCredentials.canPromptReauth() {
                return ""
            }
            return err
        }
        return ""
    }

    private func compactSubCaption() -> String {
        if let r = window.resetAt {
            let delta = max(0, r.timeIntervalSinceNow)
            return "↻ " + Duration.compact(delta)
        }
        if let err = window.error, err != "no data" {
            if err == ClaudeCredentials.reauthRequiredMessage,
               ClaudeCredentials.canPromptReauth() {
                return ""
            }
            return err
        }
        return ""
    }
}
