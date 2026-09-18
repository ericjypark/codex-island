import SwiftUI

struct CompactQuotaGauge: View {
    let usage: WindowUsage
    let mode: UsageDisplayMode
    let tint: Color
    let progress: CGFloat
    let height: CGFloat

    private let expandedWidth: CGFloat = 76

    var body: some View {
        let fraction = min(1, max(0, usage.displayedFraction(mode: mode)))
        let amount = min(1, max(0, progress))
        let shape = UnrollingQuotaShape(progress: progress)
        ZStack(alignment: .topLeading) {
            if usage.hasReading {
                shape.stroke(tint.opacity(0.24), style: StrokeStyle(lineWidth: 2 + amount, lineCap: .round, lineJoin: .round))
                shape.trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2 + amount, lineCap: .round, lineJoin: .round))
                    .opacity(fraction > 0 ? 1 : 0)
            } else {
                shape.stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 2 + amount, lineCap: .round, lineJoin: .round, dash: [2, 3]))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(usage.hasReading ? "\(usage.displayedPercentInt(mode: mode))%" : "-%")
                    .font(Typography.bodyNumber)
                    .foregroundStyle(.white.opacity(usage.hasReading ? 0.82 : 0.40))
                Spacer(minLength: 0)
                Text(L10n.tr(mode == .used ? "Used" : "Quota left"))
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .lineLimit(1)
            .frame(width: expandedWidth)
            .position(x: expandedWidth / 2, y: max(7, height / 2 - 5.5))
            .modifier(PeekContentReveal(progress: progress, start: 0.6, end: 0.9))
        }
        .frame(width: expandedWidth, height: height)
        .animation(PeekMotion.animation(opening: progress > 0), value: progress)
        .animation(.strongEaseOut, value: fraction)
    }
}

enum PeekMotion {
    static func animation(opening: Bool) -> Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: opening ? 0.44 : 0.24)
    }
}

struct PeekContentReveal: AnimatableModifier {
    var progress: CGFloat
    let start: CGFloat
    let end: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let amount = min(1, max(0, (progress - start) / (end - start)))
        content.opacity(amount * amount * (3 - 2 * amount))
    }
}
