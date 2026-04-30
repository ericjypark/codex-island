import SwiftUI

/// Two cost cells per provider — today + month-to-date — laid out horizontally
/// to mirror `ChartsBlock`'s 5h+week pair on the usage screen.
struct CostBlock: View {
    let color: Color
    let cost: ProviderCost
    let loading: Bool

    var body: some View {
        HStack(spacing: 18) {
            CostTile(color: color, window: cost.today, loading: loading)
            CostTile(color: color, window: cost.month, loading: loading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 12)
    }
}

/// One cost cell. The dollar number is the hero — 38pt brand-colored
/// monospace digits with a soft glow whose intensity grows with the
/// amount, so heavier spend feels rewarding rather than punitive. No bar,
/// no cap, no fill metaphor. Mirrors `NumericChart`'s layout (label +
/// reset glyph row on top, big value in the middle) for design-system
/// continuity with the usage screen.
struct CostTile: View {
    let color: Color
    let window: CostWindow
    let loading: Bool

    /// Locked to match `ChartTile.tileHeight` so swipe transitions don't
    /// reflow the panel.
    private static let tileHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.lowercase)
                Spacer()
                Text(resetGlyph)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("$")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                Text(formatted)
                    .font(.system(size: 38, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(glowOpacity), radius: 6)
                    .shadow(color: color.opacity(glowOpacity * 0.5), radius: 14)
                    .numericTransition(value: window.dollars)
                    .animation(.strongEaseOut, value: window.dollars)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: Self.tileHeight)
        .opacity(loading ? 0.7 : 1.0)
        .animation(.easeOut(duration: 0.18), value: loading)
    }

    /// Glow intensity scales softly with spend so a $5 day looks calm and a
    /// $1500 month looks luminous. Logarithmic so the curve doesn't blow
    /// out at the high end. Caps around 0.85 so even at peak the glow
    /// stays a halo, not a smear.
    private var glowOpacity: Double {
        let s = window.dollars
        if s <= 0 { return 0 }
        let scale = log(s + 1) / log(2000)
        return min(0.85, 0.20 + scale * 0.65)
    }

    /// Compact reset hint that mirrors `NumericChart`'s "↻ 3h" treatment so
    /// the cost screen doesn't introduce a new caption shape.
    private var resetGlyph: String {
        if let err = window.error { return err }
        return window.resetCaption
            .replacingOccurrences(of: "resets at ", with: "↻ ")
            .replacingOccurrences(of: "resets in ", with: "↻ ")
    }

    /// Drop cents above $100 so 7-digit month totals (e.g. $1432.89) don't
    /// overflow the 38pt slot. Codex stays sub-$100 typically and keeps
    /// cents; Claude month rolls over to the no-cents format naturally.
    private var formatted: String {
        let v = window.dollars
        if v < 100 { return String(format: "%.2f", v) }
        return String(format: "%.0f", v)
    }
}
