import SwiftUI

struct NumericChart: View {
    let value: Double      // 0-100
    let color: Color
    let label: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .textCase(.lowercase)
                Spacer()
                // "resets in 3h" → "↻ 3h" — same info, less prose. The
                // glyph reads at a glance; the words don't.
                Text(sub.replacingOccurrences(of: "resets in ", with: "↻ "))
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.white.opacity(0.4))
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value))")
                    .font(.system(size: 38, weight: .semibold).monospacedDigit())
                    .foregroundStyle(UrgencyColor.value(value))
                    .contentTransition(.numericText(value: value))
                    .animation(.strongEaseOut, value: value)
                Text("%")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Thin 3pt meter underneath echoes the value at a glance and
            // glows in the brand color so the big number doesn't sit alone.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.05)).frame(height: 3)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(value / 100), height: 3)
                        .shadow(color: color.opacity(0.7), radius: 4)
                        .animation(.strongEaseOut, value: value)
                }
            }
            .frame(height: 4)
        }
    }
}
