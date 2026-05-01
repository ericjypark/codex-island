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
    ///
    /// Demo mode uses a less conservative shape: history clusters around
    /// the current value (not 70% of it) with larger noise, so screen
    /// recordings actually look like a heavy user instead of a quiet one.
    private func generatePoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let n = 36
        let demo = ProcessInfo.processInfo.environment["CODEXISLAND_DEMO"] == "1"
        let startFactor: Double = demo ? 0.85 : 0.4
        let targetFactor: Double = demo ? 1.0 : 0.7
        let noiseAmpA: Double = demo ? 14 : 7
        let noiseAmpB: Double = demo ? 8 : 4
        let floor: Double = demo ? 18 : 2

        var pts: [Double] = []
        var acc = value * startFactor
        for i in 0..<n {
            let noise = sin(Double(i + seed) * 1.3) * noiseAmpA + cos(Double(i + seed) * 0.7) * noiseAmpB
            acc = acc * 0.65 + (value * targetFactor + noise) * 0.35
            pts.append(min(95, max(floor, acc)))
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
