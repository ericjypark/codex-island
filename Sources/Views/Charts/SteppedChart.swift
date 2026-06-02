import SwiftUI

struct SteppedChart: View {
    let value: Double      // 0-100
    let color: Color
    let label: String
    let sub: String
    let guide: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChartHead(value: value, label: label)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        let segments = 30
                        let filled = (value / 100) * Double(segments)
                        ForEach(0..<segments, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Double(i) < floor(filled) ? color : .white.opacity(0.10))
                                .frame(maxWidth: .infinity)
                                .frame(height: 16)
                                // ~7ms stagger across 30 cells = ~210ms sweep when
                                // a new value arrives. Stays under the 300ms budget.
                                .animation(.strongEaseOut.delay(Double(i) * 0.007), value: value)
                        }
                    }

                    if let guide {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.white.opacity(0.86))
                            .frame(width: 2, height: 22)
                            .offset(x: geo.size.width * CGFloat(guide / 100))
                            .animation(.strongEaseOut, value: guide)
                    }
                }
            }
            .frame(height: 20)
            ChartFoot(caption: sub)
        }
    }
}
