import SwiftUI

struct RingChart: View {
    let value: Double      // 0-100
    let color: Color
    let label: String
    let sub: String
    let guide: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    if let guide {
                        RingGuideTick(guide: guide)
                            .stroke(.white.opacity(0.86),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .animation(.strongEaseOut, value: guide)
                    }
                }
                .frame(width: 56, height: 56)

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
                Spacer()
            }
            Text(sub)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct RingGuideTick: Shape {
    var guide: Double

    var animatableData: Double {
        get { guide }
        set { guide = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radians = CGFloat((guide / 100) * 360 - 90) * .pi / 180
        let inner = radius - 8
        let outer = radius + 1

        var path = Path()
        path.move(to: CGPoint(
            x: center.x + cos(radians) * inner,
            y: center.y + sin(radians) * inner
        ))
        path.addLine(to: CGPoint(
            x: center.x + cos(radians) * outer,
            y: center.y + sin(radians) * outer
        ))
        return path
    }
}
