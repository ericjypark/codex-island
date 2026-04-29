import SwiftUI

/// Shared head for the three "label + big number" charts (Bar, Stepped,
/// Spark). RingChart and NumericChart render their own custom heads.
struct ChartHead: View {
    let value: Double
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.lowercase)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(value))")
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(UrgencyColor.value(value))
                    .numericTransition(value: value)
                    .animation(.strongEaseOut, value: value)
                Text("%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

struct ChartFoot: View {
    let caption: String

    var body: some View {
        Text(caption)
            .font(.system(size: 10).monospaced())
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
