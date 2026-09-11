import SwiftUI
import AppKit

/// Usage data row. The chrome (provider titles, footer chip + page dots +
/// sync status) lives in `PanelHeader` / `PanelFooter` so it stays fixed
/// while this row swipes between usage and cost screens.
struct UsageView: View {
    @ObservedObject private var store = UsageStore.shared
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    private var style: ChartStyle { pref.style }

    var body: some View {
        HStack(spacing: 0) {
            providerBlock(visibility.left)
            hairline
            if let right = visibility.right {
                providerBlock(right)
            } else if let legacy = visibility.left.legacy {
                PerModelBreakdown(provider: legacy, metric: .tokens)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, IslandPanelLayout.columnInset)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .frame(height: IslandPanelLayout.tileHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, IslandPanelLayout.horizontalInset)
    }

    @ViewBuilder
    private func providerBlock(_ provider: IslandProvider) -> some View {
        if let legacy = provider.legacy {
            ChartsBlock(color: provider.color, usage: provider == .claude ? store.claude : store.codex,
                        style: style, seed: provider == .claude ? 1 : 3, provider: legacy)
        } else {
            ConnectedUsageBlock(provider: provider)
        }
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

    /// Treat the block as needing re-auth when both windows are stuck on a
    /// reauth-actionable sentinel — an expired token (401) or a missing scope
    /// (403). Either tile alone could be a transient per-window failure, but a
    /// matching pair = the underlying token is genuinely unusable.
    private var needsReauth: Bool {
        ClaudeCredentials.isTerminalAuthFailure(usage)
    }

    var body: some View {
        Group {
            if needsReauth {
                // Dead token: the sparkline tiles carry no live data, so
                // replace them with a single centered prompt. Swapping (not
                // appending a button row) keeps the panel within its fixed
                // 188pt height instead of overflowing into the footer.
                // Same swap vocabulary as a chart-style change — the tiles
                // and the prompt trade places in one 220ms morph instead of
                // teleporting when a poll flips the auth state.
                ReauthState(color: color, usage: usage)
                    .transition(.chartSwap.animation(.chartSwap))
            } else {
                Group {
                    if usage.visibleWindows.isEmpty {
                        ProviderDataUnavailable(message: "Usage limits are not available yet.")
                    } else {
                        UsageChartsRow(color: color, style: style, seed: seed,
                            metrics: usage.visibleWindows.map { kind in
                                UsageChartMetric(id: kind.rawValue, label: kind == .fiveHour ? "5h" : "week",
                                                 window: usage.window(kind),
                                                 historyKey: "\(provider.rawValue).\(kind.rawValue)")
                            })
                    }
                }
                .transition(.chartSwap.animation(.chartSwap))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, IslandPanelLayout.columnInset)
        .animation(.chartSwap, value: usage.visibleWindows)
    }
}

/// Shown in place of the sparkline tiles when the Claude token can no longer
/// be used — expired (401) or missing the scope the usage endpoint now
/// requires (403). Both windows carry a reauth-actionable sentinel; the dead
/// numbers would only mislead, so this centered prompt takes their place. When
/// a `claude` binary is discoverable it offers one-click re-auth; otherwise it
/// shows the exact manual command from the sentinel.
struct ReauthState: View {
    let color: Color
    let usage: AppUsage

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.slash")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(color.opacity(0.85))
            if ClaudeCredentials.canPromptReauth() {
                // A scope-insufficient token (403) is not "expired" — only a
                // fresh `claude /login` re-issues the missing scope, so say
                // what is actually wrong (CodeRabbit finding on #59).
                Text(L10n.tr(usage.fiveHour.error == ClaudeCredentials.reauthRequiredMessage
                    ? "Claude re-login needed" : "Claude session expired"))
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.55))
                ReauthButton()
            } else {
                Text(usage.fiveHour.error ?? ClaudeCredentials.tokenExpiredMessage)
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }
}

/// Inline action shown below the Claude tiles when the keychain token is
/// missing the scope the usage endpoint now requires. Spawns
/// `claude auth login` and polls for the keychain to update — the chip
/// recovers on its own when the new scoped token lands.
struct ReauthButton: View {
    var title = "Re-authenticate"
    @ObservedObject private var store = UsageStore.shared
    @State private var hovered = false

    var body: some View {
        Button {
            store.reauthenticateClaude()
        } label: {
            Text(store.claudeReauthInProgress ? L10n.tr("waiting for browser…") : L10n.tr(title))
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
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .disabled(store.claudeReauthInProgress)
        .onHover { hovered = $0 }
        .animation(.hoverFade, value: hovered)
        .animation(.hoverFade, value: store.claudeReauthInProgress)
    }
}

struct UsageChartMetric: Identifiable {
    let id: String
    let label: String
    let window: WindowUsage
    let historyKey: String
}

struct UsageChartsRow: View {
    let color: Color
    let style: ChartStyle
    let seed: Int
    let metrics: [UsageChartMetric]

    /// Ring is the only style that draws a fixed-size gauge instead of
    /// stretching to the tile width. Equal tiles center each ring in its own
    /// half of the column, which leaves the gap between the two rings about
    /// twice the gaps at the column edges. Lay the rings against equal
    /// spacers instead so all three gaps match. A window with no reading
    /// falls back to NoReadingChart, which does stretch, so it keeps tiles.
    private var ringsHugContent: Bool {
        style == .ring && metrics.allSatisfy { $0.window.hasReading }
    }

    var body: some View {
        HStack(spacing: ringsHugContent ? 0 : 18) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if ringsHugContent { Spacer(minLength: 18) }
                ChartTile(style: style, color: color, labelKey: metric.label,
                          window: metric.window, seed: seed + index, historyKey: metric.historyKey,
                          centered: metrics.count == 1)
                    .frame(maxWidth: ringsHugContent ? nil : .infinity)
            }
            if ringsHugContent { Spacer(minLength: 18) }
        }
        .frame(maxWidth: metrics.count == 1 ? (style == .numeric ? 180 : 240) : .infinity)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ChartTile: View {
    let style: ChartStyle
    let color: Color
    let labelKey: String
    let window: WindowUsage
    let seed: Int
    let historyKey: String
    var centered = false
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared
    @ObservedObject private var historyStore = UsageHistoryStore.shared

    /// Locked tile height across all 5 styles so the panel size is
    /// identical regardless of what the user picks.
    private static let tileHeight = IslandPanelLayout.tileHeight

    var body: some View {
        // A window with no reading carries `usedPercent: 0` as a struct
        // default, not a measurement. Feeding that to a chart draws a
        // confident "0% used" — or a full 100% ring under the `remaining`
        // toggle — for a window we know nothing about. Gate on `hasReading`
        // and hand the tile to NoReadingChart instead.
        let value: Double? = window.hasReading
            ? window.displayedFraction(mode: usageDisplay.mode) * 100   // 0-100
            : nil
        let sub = subCaption()
        let label = L10n.tr(labelKey)

        Group {
            if let value {
                switch style {
                case .ring:    RingChart(value: value, color: color, label: label, sub: sub, centered: centered)
                case .bar:     BarChart(value: value, color: color, label: label, sub: sub)
                case .stepped: SteppedChart(value: value, color: color, label: label, sub: sub)
                case .numeric: NumericChart(value: value, color: color, label: label, sub: compactSubCaption())
                case .spark:   SparkChart(value: value, color: color, label: label, sub: sub,
                                          seed: seed, history: historyPoints())
                }
            } else {
                NoReadingChart(label: label, sub: sub)
            }
        }
        .id(style)
        // Blur + scale + opacity, all on the same strong ease-out at 220ms.
        // The blur masks the geometric mismatch between Ring and Bar so the
        // crossfade reads as one morph instead of two stacked objects.
        .transition(.chartSwap.animation(.chartSwap))
        // Width is decided by UsageChartsRow: tiled styles get an infinite
        // max there, rings hug their content so the row can space them.
        .frame(maxHeight: .infinity, alignment: .center)
        .frame(height: Self.tileHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            value.map { L10n.tr("%@, %d%%", label, Int($0)) }
                ?? L10n.tr("%@, no reading", label)
        )
        .accessibilityValue(subCaption())
    }

    /// Recorded readings for this window, mapped through the active
    /// used/remaining mode into display percent (0-100), oldest first — the
    /// same transform `value` uses, so the history and the live point agree.
    private func historyPoints() -> [Double] {
        let mode = usageDisplay.mode
        return historyStore.samples(key: historyKey).map { sample in
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
        // A terminal auth failure is handled by ReauthState (which replaces
        // the tiles entirely), so any error reaching a tile here is a genuine
        // per-window caption worth showing verbatim.
        if let err = window.error, err != "no data" {
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
            return err
        }
        return ""
    }
}
