import SwiftUI

struct CostSparkline: View {
    let series: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let scale = max(series.max() ?? 0, 0.0001)
            let points = series.enumerated().map { index, sample in
                CGPoint(
                    x: 2 + CGFloat(index) / CGFloat(max(1, series.count - 1)) * max(0, geo.size.width - 4),
                    y: 2 + (1 - CGFloat(max(0, sample) / scale)) * max(0, geo.size.height - 4)
                )
            }
            ZStack(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(color).frame(width: 4, height: 4).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
