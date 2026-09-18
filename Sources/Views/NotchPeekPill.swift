import SwiftUI

/// Glance-state percentage pill that lives outboard of each provider logo
/// while the island is in `.peek`. No background of its own — text painted
/// directly on the dark silhouette, like the logos.
///
/// Renders one of three states:
///   • value:    "32% · 2h" / "0% · 6d 23h" (active countdown) or
///               "0% · 5h" (window-length fallback at lower opacity when no
///               active resetAt is known)
///   • loading:  small pulsing dot while the first reading is unavailable
///   • errored:  "—%"         (when error is set and we have no value)
///
/// Stateless — pure function of inputs. The parent owns visibility/animation.
struct NotchPeekPill: View {
    enum Contents {
        case combined, reset, percentage, ring, gauge, stacked
    }

    let usage: WindowUsage
    let loading: Bool
    let tint: Color
    let alignment: HorizontalAlignment
    var severity: AlertEngine.Severity = .none
    /// Window-length glyph shown when no active countdown is known — must
    /// match the window actually displayed ("5h", or "7d" for the Codex
    /// weekly fallback on weekly-only plans).
    var windowLengthFallback: String = "5h"
    var contents: Contents = .combined
    var gaugeProgress: CGFloat = 0
    var gaugeHeight: CGFloat = 38
    var showsResetCaption = false
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if contents == .gauge {
                CompactQuotaGauge(usage: usage, mode: usageDisplay.mode, tint: effectiveTint,
                    progress: gaugeProgress, height: gaugeHeight)
            } else if contents == .stacked {
                stackedContent
            } else if contents == .ring {
                quotaRing
            } else if contents == .reset, showsResetCaption {
                VStack(alignment: .trailing, spacing: 1) {
                    if showSpinner {
                        LoadingDot()
                    } else if showDash {
                        Text("-").font(Typography.bodyNumber).foregroundStyle(.white.opacity(0.40))
                    } else {
                        Text(resetText ?? (windowLengthFallback.isEmpty ? "-" : windowLengthFallback))
                            .font(Typography.bodyNumber)
                            .foregroundStyle(.white.opacity(resetText == nil ? 0.45 : 0.82))
                    }
                    if usage.hasReading, resetText != nil || !windowLengthFallback.isEmpty {
                        Text(L10n.tr(resetText == nil ? "Window" : "Reset"))
                            .font(Typography.micro).foregroundStyle(.white.opacity(0.55))
                    }
                }
            } else if showSpinner {
                LoadingDot()
            } else if showDash {
                Text(contents == .reset ? "-" : "-%")
                    .font(Typography.bodyNumber)
                    .foregroundStyle(.white.opacity(0.40))
            } else if contents == .reset {
                resetLabel
            } else if contents == .percentage {
                HStack(spacing: 4) {
                    percentLabel
                    if severity != .none { warningGlyph }
                }
            } else {
                HStack(spacing: 4) {
                    if alignment == .leading {
                        // Left pill: percent on the outside (left), hours
                        // remaining on the inside (toward the notch).
                        if severity != .none { warningGlyph }
                        percentLabel
                        separator
                        resetLabel
                    } else {
                        // Right pill: mirrored so percent stays on the
                        // outside (right) and hours remaining stays inside.
                        resetLabel
                        separator
                        percentLabel
                        if severity != .none { warningGlyph }
                    }
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }

    private var stackedContent: some View {
        VStack(alignment: alignment == .leading ? .trailing : .leading, spacing: 1) {
            HStack(spacing: 4) {
                if showSpinner {
                    LoadingDot()
                } else if showDash {
                    Text("-%").font(Typography.bodyNumber).foregroundStyle(.white.opacity(0.40))
                } else {
                    if alignment == .leading, severity != .none { warningGlyph }
                    percentLabel
                    if alignment == .trailing, severity != .none { warningGlyph }
                }
            }
            .frame(height: 12)
            Text(usage.hasReading ? (resetText ?? (windowLengthFallback.isEmpty ? "-" : windowLengthFallback)) : "-")
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(!usage.hasReading ? 0.40 : (resetText == nil ? 0.45 : 0.70)))
                .frame(height: 11)
        }
    }

    private var quotaRing: some View {
        let fraction = min(1, max(0, usage.displayedFraction(mode: usageDisplay.mode)))
        return ZStack {
            if usage.hasReading {
                Circle().strokeBorder(effectiveTint.opacity(0.24), lineWidth: 2)
                Circle().inset(by: 1)
                    .trim(from: 0, to: fraction)
                    .stroke(effectiveTint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .strongEaseOut, value: fraction)
            } else {
                Circle().inset(by: 1)
                    .stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
            }
        }
        .frame(width: 20, height: 20)
    }

    private var warningGlyph: some View {
        Text("⚠")
            .font(Typography.bodyNumber)
            .foregroundStyle(effectiveTint)
    }

    private var percentLabel: some View {
        Text(percentText)
            .font(Typography.bodyNumber)
            .foregroundStyle(effectiveTint)
    }

    private var separator: some View {
        Text("·")
            .font(Typography.bodyNumber)
            .foregroundStyle(.white.opacity(0.40))
    }

    /// Lower opacity on the fallback differentiates a passive "5-hour
    /// window" label from an active "5h until reset" countdown — same
    /// glyph shape, weaker visual presence.
    private var resetLabel: some View {
        Text(resetText ?? (windowLengthFallback.isEmpty ? "-" : windowLengthFallback))
            .font(Typography.bodyNumber)
            .foregroundStyle(.white.opacity(resetText == nil ? 0.45 : (contents == .reset ? 0.82 : 0.70)))
    }

    /// Brand tint by default; alert color when above threshold so the
    /// percent + warning glyph share a consistent severity color.
    private var effectiveTint: Color {
        switch severity {
        case .none:     return tint
        case .warning:  return IslandColor.alertAmber
        case .critical: return IslandColor.alertRed
        }
    }

    /// A measured zero stays visible during refresh, just like any other reading.
    private var showSpinner: Bool {
        loading && usage.isUnreported
    }

    private var showDash: Bool {
        // No measurement to show — a failed fetch, or a window the parsed
        // response doesn't report at all (permanent on single-window Codex
        // plans since mid-2026). The old "no data" carve-out rendered the
        // sentinel as a value, which fabricated a steady "0% · 5h" — a full
        // budget under the `remaining` toggle — for a window the plan
        // doesn't have.
        !usage.hasReading
    }

    private var percentText: String {
        "\(usage.displayedPercentInt(mode: usageDisplay.mode))%"
    }

    /// Shared compact countdown (`Nm` / `Nh` / `Nd Nh`). Returns nil if
    /// there's no resetAt or the reset has already passed (happens
    /// transiently when a window rolls over before the next fetch lands).
    private var resetText: String? {
        guard let resetAt = usage.resetAt else { return nil }
        let remaining = resetAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        return Duration.compact(remaining)
    }
}

private struct LoadingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.white.opacity(0.55))
            .frame(width: 6, height: 6)
            .opacity(pulsing ? 0.30 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
