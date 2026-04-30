import SwiftUI
import AppKit

struct UsageView: View {
    let notch: NotchInfo
    @ObservedObject private var store = UsageStore.shared
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    private var style: ChartStyle { pref.style }

    var body: some View {
        VStack(spacing: 0) {
            // Top row: provider titles aligned with the system menu bar
            // (height = 22, the menu-bar item height). The notch-width
            // spacer in the middle hides inside the physical notch.
            HStack(spacing: 0) {
                providerTitle(name: "Claude", tag: store.claude.plan?.uppercased(),
                              color: IslandColor.claude, alignment: .leading)
                    .opacity(visibility.claudeVisible ? 1 : 0.30)
                    .saturation(visibility.claudeVisible ? 1 : 0)
                Color.clear.frame(width: notch.width)
                providerTitle(name: "Codex", tag: store.codex.plan?.uppercased(),
                              color: IslandColor.codex, alignment: .trailing)
                    .opacity(visibility.codexVisible ? 1 : 0.30)
                    .saturation(visibility.codexVisible ? 1 : 0)
            }
            .frame(height: 22)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, max(0, notch.height - 22 - 4))

            // Charts row: two ChartsBlocks with a 1pt vertical gradient
            // hairline divider. .clear → 6% white → .clear so the divider
            // fades at top and bottom.
            HStack(spacing: 0) {
                ChartsBlock(
                    color: visibility.claudeVisible ? IslandColor.claude : .white.opacity(0.32),
                    usage: visibility.claudeVisible ? store.claude : .dummy,
                    style: style, seed: 1
                )
                .opacity(visibility.claudeVisible ? 1 : 0.55)
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, .white.opacity(0.06), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 1)
                    .padding(.vertical, 8)
                ChartsBlock(
                    color: visibility.codexVisible ? IslandColor.codex : .white.opacity(0.32),
                    usage: visibility.codexVisible ? store.codex : .dummy,
                    style: style, seed: 3
                )
                .opacity(visibility.codexVisible ? 1 : 0.55)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Footer: hairline divider + style chip + cmd-click hint
            // (always visible here; hidden after first cycle in a later
            // commit) + live-status indicator on the right.
            LinearGradient(
                colors: [.clear, .white.opacity(0.06), .white.opacity(0.06), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 22)

            HStack(spacing: 10) {
                Text(style.label.uppercased())
                    .font(.system(size: 9, weight: .bold).monospaced())
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .contentTransition(.opacity)
                    .animation(.strongEaseOut, value: pref.style)

                if !pref.hasCycledStyle {
                    HStack(spacing: 5) {
                        Image(systemName: "command")
                            .font(.system(size: 10, weight: .semibold))
                        Text("click to cycle")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.42))
                    // Fade + small scale-from-leading on the way out so the
                    // hint deflates toward the chip rather than just vanishing.
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                }

                Spacer()

                HStack(spacing: 6) {
                    LiveDot(active: store.lastUpdated != nil && !store.loading)
                    if store.loading {
                        Text("syncing…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    } else if let updated = store.lastUpdated {
                        Text("synced")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(relative(updated))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                    } else {
                        Text("idle")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 10)
            .animation(.strongEaseOut, value: pref.hasCycledStyle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    @ViewBuilder
    private func providerTitle(
        name: String,
        tag: String?,
        color: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        // Push past where the overlay logo lands: 9 leading + 20 logo + 8 gap.
        let logoOffset: CGFloat = 9 + 20 + 8

        let content = HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if let tag {
                Text(tag)
                    .font(.system(size: 9, weight: .bold).monospaced())
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
            }
        }

        if alignment == .leading {
            HStack {
                content.padding(.leading, logoOffset)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack {
                Spacer(minLength: 0)
                content.padding(.trailing, logoOffset)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ChartsBlock: View {
    let color: Color
    let usage: AppUsage
    let style: ChartStyle
    let seed: Int

    var body: some View {
        HStack(spacing: 18) {
            ChartTile(style: style, color: color, label: "5h",
                      window: usage.fiveHour, seed: seed)
            ChartTile(style: style, color: color, label: "week",
                      window: usage.weekly, seed: seed + 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

struct ChartTile: View {
    let style: ChartStyle
    let color: Color
    let label: String
    let window: WindowUsage
    let seed: Int

    /// Locked tile height across all 5 styles so the panel size is
    /// identical regardless of what the user picks.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        let value = window.usedPercent * 100   // 0-100
        let sub = subCaption()

        Group {
            switch style {
            case .ring:    RingChart(value: value, color: color, label: label, sub: sub)
            case .bar:     BarChart(value: value, color: color, label: label, sub: sub)
            case .stepped: SteppedChart(value: value, color: color, label: label, sub: sub)
            case .numeric: NumericChart(value: value, color: color, label: label, sub: sub)
            case .spark:   SparkChart(value: value, color: color, label: label, sub: sub, seed: seed)
            }
        }
        .id(style)
        // Blur + scale + opacity, all on the same strong ease-out at 220ms.
        // The blur masks the geometric mismatch between Ring and Bar so the
        // crossfade reads as one morph instead of two stacked objects.
        .transition(.chartSwap.animation(.chartSwap))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
    }

    private func subCaption() -> String {
        if let err = window.error { return err }
        guard let r = window.resetAt else { return "" }
        let delta = max(0, r.timeIntervalSinceNow)
        return "resets in \(formatDelta(delta))"
    }

    private func formatDelta(_ s: TimeInterval) -> String {
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s/60))m" }
        if s < 86400 { return "\(Int(s/3600))h" }
        return "\(Int(s/86400))d"
    }
}
