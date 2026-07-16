import SwiftUI

/// Glance-state percentage pill that lives outboard of each provider logo
/// while the island is in `.peek`. No background of its own — text painted
/// directly on the dark silhouette, like the logos.
///
/// Renders one of three states:
///   • value:    "32% · 2h" / "0% · 6d 23h" (active countdown) or
///               "0% · 5h" (window-length fallback at lower opacity when no
///               active resetAt is known)
///   • loading:  small pulsing dot (only when `loading && usedPercent == 0`)
///   • errored:  "—%"         (when error is set and we have no value)
///
/// Stateless — pure function of inputs. The parent owns visibility/animation.
struct NotchPeekPill: View {
    let usage: WindowUsage
    let loading: Bool
    let tint: Color
    let alignment: HorizontalAlignment
    var severity: AlertEngine.Severity = .none
    @ObservedObject private var usageDisplay = UsageDisplayModeStore.shared

    var body: some View {
        Group {
            if showSpinner {
                LoadingDot()
            } else if showDash {
                Text("—%")
                    .font(Typography.bodyNumber)
                    .foregroundStyle(.white.opacity(0.40))
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
        Text(resetText ?? "5h")
            .font(Typography.bodyNumber)
            .foregroundStyle(.white.opacity(resetText == nil ? 0.45 : 0.70))
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

    private var hasValue: Bool {
        usage.usedPercent > 0 || usage.error == nil
    }

    /// Spinner only fires for the cold-start case (loading AND we have nothing
    /// to show). If we have a prior value, keep showing it during refresh —
    /// same principle as UsageStore.isErrorOnly's "don't blank the panel" rule.
    private var showSpinner: Bool {
        loading && usage.usedPercent == 0 && usage.error == nil
    }

    private var showDash: Bool {
        // "no data" is our sentinel for "API returned null for this window"
        // (typically a fresh 5h period before the first OAuth call lands).
        // Treat it as a passive non-error so the pill still renders with
        // the 5h window-length fallback instead of collapsing to "—%".
        guard let err = usage.error, err != "no data" else { return false }
        return usage.usedPercent == 0
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
