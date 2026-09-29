import SwiftUI

struct SparkChart: View {
    let value: Double
    let color: Color
    let label: String
    let sub: String
    let seed: Int
    var history: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChartHead(value: value, label: label)
            Group {
                if history.count >= 2 {
                    GeometryReader { geo in
                        let points = history.enumerated().map { index, sample in
                            CGPoint(
                                x: 3 + CGFloat(index) / CGFloat(history.count - 1) * max(0, geo.size.width - 6),
                                y: 3 + (1 - CGFloat(min(100, max(0, sample)) / 100)) * max(0, geo.size.height - 6)
                            )
                        }
                        let line = SparklinePath.line(through: points)
                        ZStack(alignment: .bottom) {
                            Rectangle()
                                .fill(.white.opacity(0.07))
                                .frame(height: 0.5)
                            SparklinePath.area(under: line, points: points, baseline: geo.size.height)
                                .fill(LinearGradient(colors: [color.opacity(0.18), color.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                            line.stroke(color.opacity(0.9),
                                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            if let last = points.last {
                                Circle()
                                    .fill(color)
                                    .overlay(Circle().stroke(.black, lineWidth: 0.75))
                                    .frame(width: 5, height: 5)
                                    .position(last)
                            }
                        }
                    }
                    .accessibilityLabel(L10n.tr("Recorded usage"))
                } else {
                    Text(L10n.tr("History appears after more refreshes."))
                        .font(Typography.micro)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .frame(height: 38)
            ChartFoot(caption: sub)
        }
    }
}
