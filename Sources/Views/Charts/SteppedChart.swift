import SwiftUI

struct SteppedChart: View {
    let value: Double      // 0-100
    let color: Color
    let label: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChartHead(value: value, label: label)
            HStack(spacing: 2) {
                let segments = 20
                let filled = (value / 100) * Double(segments)
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(i) < floor(filled) ? color : .white.opacity(0.06))
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                        // 10ms stagger across cells gives a brief "fill"
                        // sweep when a new value arrives. Total animation
                        // is still under 300ms (200ms across all 20).
                        .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.01), value: value)
                }
            }
            ChartFoot(caption: sub)
        }
    }
}
