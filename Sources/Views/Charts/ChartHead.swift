import SwiftUI

struct ChartHead: View {
    let value: Double
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 4)
            QuotaValue(reading: QuotaChartReading(id: label, label: label, value: value, caption: ""),
                       mode: UsageDisplayModeStore.shared.mode, size: 32, weight: .semibold)
                .animation(reduceMotion ? nil : .strongEaseOut, value: DisplayNumber.percent(value))
        }
    }
}

struct ChartFoot: View {
    let caption: String

    var body: some View {
        Text(caption)
            .font(Typography.caption)
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
