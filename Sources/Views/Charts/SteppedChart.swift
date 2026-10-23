import SwiftUI

struct SteppedChart: View {
    let value: Double
    let color: Color
    let label: String
    let sub: String
    var rowLayout = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if rowLayout {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        ChartHead(value: value, label: label, valueSize: 24)
                        ChartFoot(caption: sub)
                    }
                    .frame(width: 132, alignment: .leading)
                    segments.frame(height: 20)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ChartHead(value: value, label: label)
                    segments.frame(height: 16)
                    ChartFoot(caption: sub)
                }
            }
        }
    }

    private var segments: some View {
        HStack(spacing: 3) {
            let segments = 20
            let filled = Double(DisplayNumber.percent(value)) / 100 * Double(segments)
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
        .animation(reduceMotion ? nil : .strongEaseOut, value: value)
        .accessibilityHidden(true)
    }
}
