import SwiftUI

struct RingChart: View {
    let value: Double      // 0-100
    let color: Color
    let label: String
    let sub: String
    var centered = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.white.opacity(0.07), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.001, value / 100))
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        // No animate-from-zero on charts. The only animation
                        // here fires when polling delivers a new value
                        // (old → new), which makes the trim feel alive
                        // without ever flashing 0%.
                        .animation(.strongEaseOut, value: value)
                }
                .frame(width: centered ? 64 : 56, height: centered ? 64 : 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(Typography.label)
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.lowercase)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(value))")
                            .font(Typography.chartValue)
                            .foregroundStyle(UrgencyColor.value(value, mode: UsageDisplayModeStore.shared.mode))
                            .numericTransition(value: value)
                            .animation(.strongEaseOut, value: value)
                        Text("%")
                            .font(Typography.label)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            Text(sub)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
