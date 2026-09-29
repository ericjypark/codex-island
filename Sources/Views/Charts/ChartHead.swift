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
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(value))")
                    .font(Typography.quotaValue)
                    .foregroundStyle(UrgencyColor.value(value, mode: UsageDisplayModeStore.shared.mode))
                    .numericTransition(value: value)
                    .animation(reduceMotion ? nil : .strongEaseOut, value: value)
                Text("%")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .fixedSize()
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
