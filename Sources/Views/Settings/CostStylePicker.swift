import SwiftUI

/// Four-tile picker for the default cost view style. Mirror of
/// `ChartStylePicker` for the cost screen — same visual language so the
/// Display tab reads as one cohesive picker section. Selecting a tile
/// also updates the `CostStylePref.shared` singleton via the binding.
struct CostStylePicker: View {
    @Binding var selected: CostStyle

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CostStyle.allCases, id: \.self) { style in
                tile(for: style)
            }
        }
    }

    @ViewBuilder
    private func tile(for style: CostStyle) -> some View {
        let isOn = (style == selected)
        Button {
            selected = style
        } label: {
            VStack(spacing: 7) {
                preview(for: style)
                    .frame(height: 34)
                Text(style.label)
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
    }

    @ViewBuilder
    private func preview(for style: CostStyle) -> some View {
        let claude = IslandColor.claude
        switch style {
        case .dollar:
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("$")
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.5))
                Text("87")
                    .font(Typography.previewNumber)
                    .foregroundStyle(claude)
            }
        case .multi:
            HStack(alignment: .bottom, spacing: 4) {
                Capsule().fill(.white.opacity(0.20))
                    .frame(width: 8, height: 6)
                Capsule().fill(claude)
                    .frame(width: 8, height: 18)
                    .shadow(color: claude.opacity(0.6), radius: 3)
            }
        case .tokens:
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("2.4")
                    .font(Typography.previewNumber)
                    .foregroundStyle(claude)
                Text("M")
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .spark:
            CostSparkPath()
                .stroke(claude, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .shadow(color: claude.opacity(0.6), radius: 2)
                .frame(width: 32, height: 16)
        }
    }
}

/// Static ascending sparkline for the TREND tile preview. Always trends
/// upward (slight wiggle) to match the always-cumulative nature of the
/// real cost sparkline.
private struct CostSparkPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pts: [(CGFloat, CGFloat)] = [
            (0.00, 0.92), (0.16, 0.78),
            (0.34, 0.65), (0.50, 0.50),
            (0.69, 0.38), (0.84, 0.22),
            (1.00, 0.10),
        ]
        for (i, pt) in pts.enumerated() {
            let cgp = CGPoint(x: rect.minX + rect.width * pt.0,
                              y: rect.minY + rect.height * pt.1)
            if i == 0 { p.move(to: cgp) } else { p.addLine(to: cgp) }
        }
        return p
    }
}
