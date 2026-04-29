import SwiftUI

struct BarChart: View {
    let value: Double      // 0-100
    let color: Color
    let label: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChartHead(value: value, label: label)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.06)).frame(height: 4)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(value / 100), height: 4)
                        .animation(.easeOut(duration: 0.4), value: value)
                    // Tick marks at quartiles. Subtle (12% white) so they
                    // hint at scale without competing with the fill.
                    ForEach([0.25, 0.5, 0.75], id: \.self) { p in
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 1, height: 8)
                            .offset(x: geo.size.width * p)
                    }
                }
            }
            .frame(height: 8)
            ChartFoot(caption: sub)
        }
    }
}
