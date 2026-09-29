import SwiftUI

struct RingChart: View {
    let value: Double
    let color: Color
    let label: String
    let sub: String
    var centered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 4.5)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, value / 100)))
                        .stroke(color, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .strongEaseOut, value: value)
                }
                .frame(width: centered ? 60 : 52, height: centered ? 60 : 52)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(Typography.label)
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(value))")
                            .font(Typography.quotaValue)
                            .foregroundStyle(UrgencyColor.value(value, mode: UsageDisplayModeStore.shared.mode))
                            .numericTransition(value: value)
                        Text("%")
                            .font(Typography.micro)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .fixedSize()
                }
            }
            ChartFoot(caption: sub)
        }
    }
}
