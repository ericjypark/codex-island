import SwiftUI

struct QuotaArc: Shape {
    var fraction: Double = 1
    var radiusRatio: CGFloat = 1
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let fraction = min(1, max(0, fraction))
        guard fraction > 0 else { return Path() }
        let radius = max(0, min(rect.width, rect.height) / 2 - 3) * radiusRatio
        let count = max(2, Int(180 * fraction))
        var path = Path()
        for index in 0...count {
            let progress = Double(index) / Double(count)
            let angle: Double = (135 + 270 * fraction * progress) * Double.pi / 180
            let point = CGPoint(x: rect.midX + CGFloat(cos(angle)) * radius,
                                y: rect.midY + CGFloat(sin(angle)) * radius)
            if index == 0 { path.move(to: point) }
            else { path.addLine(to: point) }
        }
        return path
    }
}

struct OrbitChart: View {
    let readings: [QuotaChartReading]
    let color: Color
    let mode: UsageDisplayMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func inner(_ reading: QuotaChartReading) -> Bool {
        readings.count > 1 && reading.id == readings.first?.id
    }

    private func tint(_ reading: QuotaChartReading) -> Color {
        if readings.count > 2, reading.id == readings[1].id { return color.opacity(0.7) }
        return inner(reading) ? QuotaPalette.shortTerm(color) : color
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                ForEach(readings) { reading in
                    let index = readings.firstIndex { $0.id == reading.id } ?? 0
                    let ratio: CGFloat = readings.count > 2 ? CGFloat(15 + 12 * index) / 39 : inner(reading) ? 27/39 : 1
                    if reading.amount == nil {
                        QuotaArc(radiusRatio: ratio)
                            .stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        if let value = reading.value {
                            QuotaArc(fraction: value / 100, radiusRatio: ratio)
                                .stroke(tint(reading), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        }
                    }
                }
            }
            .frame(width: 104, height: 104)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(readings) { reading in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(tint(reading)).frame(width: 4, height: 4).accessibilityHidden(true)
                            Text(reading.label).font(Typography.label).foregroundStyle(tint(reading))
                                .lineLimit(1).frame(width: 44, alignment: .leading).help(reading.label)
                            QuotaValue(reading: reading, mode: mode, size: readings.count == 1 ? 32 : 26)
                        }
                        QuotaCaption(caption: reading.caption).padding(.leading, 12)
                    }
                    .help(readings.count > 1 ? L10n.tr(inner(reading) ? "Inner ring" : "Outer ring") : reading.label)
                    .modifier(QuotaAccessibility(reading: reading, mode: mode))
                }
            }
            .frame(width: 144, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : .strongEaseOut, value: readings.map(\.value))
    }
}
