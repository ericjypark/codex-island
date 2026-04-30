import SwiftUI

/// Cumulative-spend sparkline. The series is monotonically non-decreasing
/// so the line always ascends — feels rewarding rather than volatile.
/// Brand-color stroke with a glow underneath, plus a soft gradient fill
/// from the line down to the baseline so the area under the curve feels
/// substantial.
struct CostSparkline: View {
    let series: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = series.max() ?? 0
            // Floor the denominator so a flat / single-point series doesn't
            // divide by zero and so very small values still draw something.
            let scale = max(maxV, 0.0001)
            let n = series.count

            if n < 2 {
                // One point or fewer — render a tiny dot anchored at the
                // bottom-left so the cell isn't visually empty.
                Circle()
                    .fill(color)
                    .frame(width: 3, height: 3)
                    .position(x: 1.5, y: geo.size.height - 1.5)
                    .shadow(color: color.opacity(0.6), radius: 3)
            } else {
                let stepX = geo.size.width / CGFloat(n - 1)

                ZStack {
                    // Filled area under the curve. Gradient drops to clear
                    // at the bottom so the fill reads as "weight" without
                    // competing with the stroke.
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (i, v) in series.enumerated() {
                            let x = CGFloat(i) * stepX
                            let y = geo.size.height * (1 - CGFloat(v / scale))
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [color.opacity(0.45), color.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    // Stroke line on top, with a soft glow so the line
                    // glows against the dark panel.
                    Path { p in
                        let firstY = geo.size.height * (1 - CGFloat(series[0] / scale))
                        p.move(to: CGPoint(x: 0, y: firstY))
                        for (i, v) in series.enumerated().dropFirst() {
                            let x = CGFloat(i) * stepX
                            let y = geo.size.height * (1 - CGFloat(v / scale))
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.7), radius: 3)
                }
            }
        }
    }
}
