import SwiftUI

/// Five-tile picker for the default chart style. Replaces the
/// undocumented ⌘-click cycle gesture (which still works in the panel).
/// Each tile renders a tiny preview using the brand terracotta — not
/// pixel-identical to the live chart, but the same vocabulary so the
/// picker reads as a real preview, not an icon set.
struct ChartStylePicker: View {
    @Binding var selected: ChartStyle

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ChartStyle.allCases, id: \.self) { style in
                tile(for: style)
            }
        }
    }

    @ViewBuilder
    private func tile(for style: ChartStyle) -> some View {
        let isOn = (style == selected)
        Button {
            selected = style
            if !StylePref.shared.hasCycledStyle {
                StylePref.shared.hasCycledStyle = true
            }
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
    private func preview(for style: ChartStyle) -> some View {
        let claude = IslandColor.claude
        switch style {
        case .ring:
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.10), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: 0.35)
                    .stroke(claude, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
        case .bar:
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                Capsule().fill(claude)
                    .frame(width: 28 * 0.35)
            }
            .frame(width: 28, height: 6)
        case .stepped:
            HStack(spacing: 1.5) {
                ForEach(0..<8) { i in
                    RoundedRectangle(cornerRadius: 0.75)
                        .fill(i < 3 ? claude : .white.opacity(0.10))
                        .frame(width: 2, height: 12)
                }
            }
            .frame(width: 28, height: 14)
        case .numeric:
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("35")
                    .font(Typography.previewNumber)
                    .foregroundStyle(claude)
                Text("%")
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .spark:
            SparkPath()
                .stroke(claude, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 16)
        }
    }
}

/// Static spark preview path — fixed shape so the tile reads consistently
/// across the picker, regardless of the user's actual usage trace.
private struct SparkPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pts: [(CGFloat, CGFloat)] = [
            (0.00, 0.75), (0.16, 0.55),
            (0.34, 0.70), (0.50, 0.30),
            (0.69, 0.45), (0.84, 0.18),
            (1.00, 0.40)
        ]
        for (i, pt) in pts.enumerated() {
            let cgp = CGPoint(x: rect.minX + rect.width * pt.0,
                              y: rect.minY + rect.height * pt.1)
            if i == 0 { p.move(to: cgp) } else { p.addLine(to: cgp) }
        }
        return p
    }
}
