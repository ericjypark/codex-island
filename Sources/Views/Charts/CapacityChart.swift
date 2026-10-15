import SwiftUI

struct CapacityChart: View {
    let reading: QuotaChartReading
    let color: Color
    let mode: UsageDisplayMode
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reading.label).font(Typography.label).foregroundStyle(.white.opacity(0.65))
                .lineLimit(1).help(reading.label)
            HStack(spacing: 6) {
                QuotaValue(reading: reading, mode: mode, size: compact ? 28 : 40)
                Canvas { context, size in
                    let columns = 20
                    let rows = 100 / columns
                    let plotWidth = min(size.width * (compact ? 1 : 0.8), size.height * 3.5)
                    let plotHeight = plotWidth / 3.5
                    let columnStride = plotWidth / CGFloat(columns)
                    let rowStride = plotHeight / CGFloat(rows)
                    let cellSize = min(columnStride, rowStride) * 0.7
                    let leadingInset = (size.width - plotWidth) / 2
                    let topInset = (size.height - plotHeight) / 2
                    for cell in 0..<100 {
                        let rect = CGRect(x: leadingInset + CGFloat(cell % columns) * columnStride + (columnStride - cellSize) / 2,
                                          y: topInset + CGFloat(cell / columns) * rowStride + (rowStride - cellSize) / 2,
                                          width: cellSize, height: cellSize)
                        let path = Path(roundedRect: rect, cornerRadius: 1)
                        let amount = min(1, max(0, (reading.value ?? 0) - Double(cell)))
                        context.fill(path, with: .color(amount > 0 ? color.opacity(0.4 + 0.6 * amount) : .white.opacity(0.15)))
                    }
                }
                .frame(height: 64)
                .opacity(reading.amount == nil ? 1 : 0)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
            QuotaCaption(caption: reading.caption)
        }
        .frame(maxWidth: .infinity)
        .modifier(QuotaAccessibility(reading: reading, mode: mode))
    }
}
