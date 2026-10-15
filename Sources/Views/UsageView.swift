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
        HStack(alignment: .center, spacing: 0) {
            providerBlock(visibility.left)
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
        .frame(minHeight: IslandPanelLayout.tileHeight, alignment: .center)
        .overlay { hairline.allowsHitTesting(false) }
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
                            metrics: usage.visibleWindows.filter { $0 != .monthly }.map { kind in
                                UsageChartMetric(id: kind.rawValue, label: kind.labelKey,
                                                 window: usage.window(kind),
                                                 historyKey: "\(provider.rawValue).\(kind.rawValue)")
                            }, credits: usage.visibleWindows.contains(.monthly) ? usage.monthly : nil)
                    }
                }
                .transition(.chartSwap.animation(.chartSwap))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
    var credits: WindowUsage? = nil
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared
    @ObservedObject private var historyStore = UsageHistoryStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var readings: [QuotaChartReading] {
        metrics.enumerated().map { index, metric in
            let window = metric.window
            let mode = usageDisplay.mode
            let value = window.hasPercentageReading ? Double(DisplayNumber.percent(window.displayedFraction(mode: mode) * 100)) : nil
            let history = style == .telemetry ? historyStore.samples(key: metric.historyKey).map {
                Double(DisplayNumber.percent(WindowUsage(usedPercent: $0.used, resetAt: nil, error: nil)
                    .displayedFraction(mode: mode) * 100))
            } : []
            return QuotaChartReading(id: metric.id, label: L10n.tr(metric.label), value: value,
                caption: caption(window), amount: window.isUnlimitedAmount ? window.usedAmount.map { UsageCreditDisplay.currency($0, code: window.currencyCode) } : nil, history: value.map {
                    SparklineSamples.displayed(history: history, value: $0, seed: seed + index,
                                               isDemo: AppEnvironment.isDemo)
                } ?? [])
        }
    }

    var body: some View {
        let readings = readings
        VStack(alignment: .leading, spacing: 16) {
            if !readings.isEmpty {
                charts(readings)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.count > 2 ? 180 : IslandPanelLayout.tileHeight)
                    .id(style)
                    .transition(reduceMotion ? .opacity : .chartSwap)
            }
            if let credits {
                UsageCreditsSummary(window: credits, color: color, mode: usageDisplay.mode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? nil : .chartSwap, value: style)
    }

    private func charts(_ readings: [QuotaChartReading]) -> some View {
        Group {
            switch style {
            case .rails:
                RailsChart(readings: readings, color: color, mode: usageDisplay.mode)
            case .ring:
                OrbitChart(readings: readings, color: color, mode: usageDisplay.mode)
            case .capacity:
                HStack(spacing: 18) {
                    ForEach(readings) { reading in
                        CapacityChart(reading: reading, color: color, mode: usageDisplay.mode,
                                      compact: readings.count > 1)
                    }
                }
            case .telemetry:
                TelemetryChart(readings: readings, color: color, mode: usageDisplay.mode)
            case .stepped:
                HStack(spacing: 18) {
                    ForEach(readings) { reading in
                        Group {
                            if let value = reading.value {
                                SteppedChart(value: value, color: color, label: reading.label, sub: reading.caption)
                            } else if let amount = reading.amount {
                                UsageAmountChart(label: reading.label, amount: amount, sub: reading.caption)
                            } else {
                                NoReadingChart(label: reading.label, sub: reading.caption)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .help(reading.caption)
                        .modifier(QuotaAccessibility(reading: reading, mode: usageDisplay.mode))
                    }
                }
            }
        }
    }

    func caption(_ window: WindowUsage) -> String {
        if let amounts = window.amountCaption {
            if let error = window.error, error != "no data" { return error + " · " + amounts }
            guard let resetAt = window.resetAt else { return amounts }
            return amounts + " · " + L10n.tr("resets in %@", Duration.compact(max(0, resetAt.timeIntervalSinceNow)))
        }
        if let reset = window.resetAt {
            return L10n.tr("resets in %@", Duration.compact(max(0, reset.timeIntervalSinceNow)))
        }
        if let error = window.error, error != "no data" { return error }
        return ""
    }
}

private struct UsageAmountChart: View {
    let label: String
    let amount: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.6))
            Text(amount)
                .font(Typography.bigNumber)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            ChartFoot(caption: sub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
