import SwiftUI

struct SparkChart: View {
    let value: Double      // 0-100
    let color: Color
    let label: String
    let sub: String
    let seed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChartHead(value: value, label: label)
            SparkSVG(value: value, color: color, seed: seed)
                .frame(height: 56)
                .animation(.strongEaseOut, value: value)
            ChartFoot(caption: sub)
        }
    }
}

private struct SparkSVG: View {
    let value: Double
    let color: Color
    let seed: Int

    /// Synthesize 36 plausible-looking historical points around the current
    /// value. Real history would need a usage time-series API neither
    /// provider exposes — this is decorative and clearly so.
    private func generatePoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let n = 36
        var pts: [Double] = []
        var acc = value * 0.4
        for i in 0..<n {
            let noise = sin(Double(i + seed) * 1.3) * 7 + cos(Double(i + seed) * 0.7) * 4
            acc = acc * 0.65 + (value * 0.7 + noise) * 0.35
            pts.append(min(98, max(2, acc)))
        }
        if !pts.isEmpty { pts[pts.count - 1] = value }
        return pts.enumerated().map { (i, p) in
            CGPoint(
                x: CGFloat(i) * (width / CGFloat(n - 1)),
                y: height - CGFloat(p / 100) * (height - 8) - 4
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pts = generatePoints(width: w, height: h)
            let baselineY = h - CGFloat(value / 100) * (h - 8) - 4
            ZStack {
                // Quartile rules at 4% white, barely there.
                ForEach([0.25, 0.5, 0.75], id: \.self) { p in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h * p))
                        path.addLine(to: CGPoint(x: w, y: h * p))
                    }
                    .stroke(.white.opacity(0.04), lineWidth: 1)
                }
                // Dotted threshold at the current value — the line reading
                // "this is now" against the synthesized history.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: baselineY))
                    path.addLine(to: CGPoint(x: w, y: baselineY))
                }
                .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                // Gradient area fill under the curve.
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [color.opacity(0.28), color.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))

                // Curve itself.
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

                // End cursor: outer halo + solid dot at the latest point.
                if let last = pts.last {
                    Circle().fill(color.opacity(0.15)).frame(width: 10, height: 10).position(last)
                    Circle().fill(color).frame(width: 5, height: 5).position(last)
                }
            }
        }
    }
}
