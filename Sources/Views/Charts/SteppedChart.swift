import SwiftUI

struct SteppedChart: View {
    let value: Double
    let color: Color
    let label: String
    let sub: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartHead(value: value, label: label)
            HStack(spacing: 3) {
                let segments = 20
                let filled = min(100, max(0, value)) / 100 * Double(segments)
                ForEach(0..<segments, id: \.self) { index in
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.12))
                            Rectangle().fill(color)
                                .frame(width: geometry.size.width * min(1, max(0, filled - Double(index))))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                    }
                }
            }
            .frame(height: 12)
            .animation(reduceMotion ? nil : .strongEaseOut, value: value)
            .accessibilityHidden(true)
            ChartFoot(caption: sub)
        }
    }
}
