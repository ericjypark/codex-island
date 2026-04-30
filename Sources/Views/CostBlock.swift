import SwiftUI

/// Two cost cells per provider — today + month-to-date — laid out horizontally
/// to mirror `ChartsBlock`'s 5h+week pair on the usage screen.
struct CostBlock: View {
    let color: Color
    let cost: ProviderCost

    var body: some View {
        HStack(spacing: 18) {
            CostTile(color: color, window: cost.today)
            CostTile(color: color, window: cost.month)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

/// One cost cell. Mirrors `SteppedChart`'s structure (head + 30-segment bar +
/// foot) with the same type scale, opacity ladder, and stagger timing — only
/// the head shows a dollar amount instead of a percentage and the bar fills
/// against `window.cap` instead of 100.
struct CostTile: View {
    let color: Color
    let window: CostWindow

    /// Locked to match `ChartTile.tileHeight` so swipe transitions don't
    /// reflow the panel.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CostHead(window: window)
            HStack(spacing: 2) {
                let segments = 30
                let filled = window.fillFraction * Double(segments)
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Double(i) < floor(filled) ? color : .white.opacity(0.10))
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                        .animation(.strongEaseOut.delay(Double(i) * 0.007), value: window.dollars)
                }
            }
            ChartFoot(caption: window.error ?? window.resetCaption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
    }
}

/// Cost-screen analog of `ChartHead`. Identical type scale, opacity tiers,
/// and animations — the only differences are the `$` prefix (instead of `%`
/// suffix) and the two-decimal dollar formatting. Urgency color drives off
/// `fillFraction * 100` so the digits warn red/amber when spend approaches
/// or exceeds the visual cap.
private struct CostHead: View {
    let window: CostWindow

    var body: some View {
        let urgency = window.fillFraction * 100
        HStack(alignment: .firstTextBaseline) {
            Text(window.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.lowercase)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("$")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(String(format: "%.2f", window.dollars))
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(UrgencyColor.value(urgency))
                    .numericTransition(value: window.dollars)
                    .animation(.strongEaseOut, value: window.dollars)
            }
        }
    }
}
