import SwiftUI

/// Single tile in the chart-style or cost-style picker grid. Pre-tilted
/// chrome — cobalt-tinted background when selected, tiny preview rendered
/// by the caller, label at the bottom. Used by `ChartStylePicker` and
/// `CostStylePicker`.
struct StyleTile<Preview: View>: View {
    let displayLabel: String
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview()
                    .frame(height: 34)
                    .accessibilityHidden(true)
                Text(displayLabel)
                    .font(Typography.micro)
                    .foregroundStyle(isOn
                        ? Color(red: 0.58, green: 0.75, blue: 1.0)
                        : .white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.horizontal, 6)
            .padding(.bottom, 10)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(isOn
                          ? IslandColor.cobalt.opacity(0.14)
                          : .white.opacity(0.025))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(isOn
                                ? IslandColor.cobalt.opacity(0.6)
                                : .clear, lineWidth: 1)
                    }
                    .shadow(color: isOn
                            ? IslandColor.cobalt.opacity(0.18)
                            : .clear, radius: 9)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayLabel)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
