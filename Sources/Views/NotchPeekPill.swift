import SwiftUI

/// Glance-state percentage pill that lives outboard of each provider logo
/// while the island is in `.peek`. No background of its own — text painted
/// directly on the dark silhouette, like the logos.
///
/// Renders one of three states:
///   • value:    "32% · 2h"  (or "32%" when no resetAt is known)
///   • loading:  small pulsing dot (only when `loading && usedPercent == 0`)
///   • errored:  "—%"         (when error is set and we have no value)
///
/// Stateless — pure function of inputs. The parent owns visibility/animation.
struct NotchPeekPill: View {
    let usage: WindowUsage
    let loading: Bool
    let tint: Color
    let alignment: HorizontalAlignment

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
                    Text(percentText)
                        .font(Typography.bodyNumber)
                        .foregroundStyle(tint)
                    if let reset = resetText {
                        Text("·")
                            .font(Typography.bodyNumber)
                            .foregroundStyle(.white.opacity(0.40))
                        Text(reset)
                            .font(Typography.bodyNumber)
                            .foregroundStyle(.white.opacity(0.70))
                    }
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
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
        usage.error != nil && usage.usedPercent == 0
    }

    private var percentText: String {
        "\(Int((usage.usedPercent * 100).rounded()))%"
    }

    /// `Nh` when ≥ 1h remaining, `Nm` under 1h. Returns nil if there's no
    /// resetAt or the reset has already passed (happens transiently when a
    /// window rolls over before the next fetch lands).
    private var resetText: String? {
        guard let resetAt = usage.resetAt else { return nil }
        let remaining = resetAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        if remaining >= 3600 {
            return "\(Int((remaining / 3600).rounded(.down)))h"
        } else {
            return "\(max(1, Int((remaining / 60).rounded(.down))))m"
        }
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
