import SwiftUI

struct BarChart: View {
    let value: Double
    let color: Color
    let label: String
    let sub: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartHead(value: value, label: label)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, value / 100))))
                        .animation(reduceMotion ? nil : .strongEaseOut, value: value)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            ChartFoot(caption: sub)
        }
    }
}
