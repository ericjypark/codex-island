import SwiftUI

struct TelemetryChart: View {
    let readings: [QuotaChartReading]
    let color: Color
    let mode: UsageDisplayMode

    var body: some View {
        VStack(spacing: 8) {
            ForEach(readings) { reading in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(reading.label).font(Typography.label).foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1).help(reading.label)
                        QuotaCaption(caption: reading.caption)
                        Spacer(minLength: 0)
                        QuotaValue(reading: reading, mode: mode, size: readings.count == 1 ? 32 : 22)
                    }
                    trace(reading)
                        .frame(height: readings.count == 1 ? 60 : 24)
                }
                .modifier(QuotaAccessibility(reading: reading, mode: mode))
            }
        }
        .help(L10n.tr("Recorded observations in order, not elapsed time."))
    }

    @ViewBuilder
    private func trace(_ reading: QuotaChartReading) -> some View {
        if reading.value != nil, reading.history.count >= 2 {
            GeometryReader { geometry in
                let points = reading.history.enumerated().map { index, sample in
                    CGPoint(x: 2 + CGFloat(index) / CGFloat(reading.history.count - 1) * max(0, geometry.size.width - 4),
                            y: 2 + (1 - CGFloat(min(100, max(0, sample)) / 100)) * max(0, geometry.size.height - 4))
                }
                let line = SparklinePath.line(through: points)
                ZStack {
                    SparklinePath.area(under: line, points: points, baseline: geometry.size.height - 2)
                        .fill(color.opacity(0.12))
                    line.stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    if let last = points.last {
                        Circle().fill(color).frame(width: 4, height: 4).position(last)
                    }
                }
            }
            .accessibilityHidden(true)
        } else {
            Text(reading.amount != nil ? L10n.tr("Unlimited") : reading.value == nil ? L10n.tr("No recorded reading") : L10n.tr("History appears after more refreshes."))
                .font(Typography.micro).foregroundStyle(.white.opacity(0.6))
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
