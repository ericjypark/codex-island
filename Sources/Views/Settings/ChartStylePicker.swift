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
                StyleTile(
                    displayLabel: style.label,
                    isOn: style == selected,
                    action: {
                        selected = style
                        if !StylePref.shared.hasCycledStyle {
                            StylePref.shared.hasCycledStyle = true
                        }
                    }
                ) {
                    preview(for: style)
                }
            }
        }
    }

    @ViewBuilder
    private func preview(for style: ChartStyle) -> some View {
        let claude = IslandColor.claude
        switch style {
        case .rails:
            VStack(spacing: 6) {
                ForEach(0..<2) { index in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(claude).frame(width: index == 0 ? 10 : 18)
                    }
                    .frame(width: 30, height: 3)
                }
            }
        case .ring:
            ZStack {
                QuotaArc().stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                QuotaArc(fraction: 0.35).stroke(claude, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                QuotaArc(radiusRatio: 0.65).stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                QuotaArc(fraction: 0.2, radiusRatio: 0.65)
                    .stroke(QuotaPalette.shortTerm(claude), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: 32, height: 32)
        case .capacity:
            VStack(spacing: 2) {
                ForEach(0..<5) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<5) { column in
                            RoundedRectangle(cornerRadius: 0.6)
                                .fill(row * 5 + column < 9 ? claude : .white.opacity(0.15))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
        case .stepped:
            HStack(spacing: 1.5) {
                ForEach(0..<8) { i in
                    RoundedRectangle(cornerRadius: 0.75)
                        .fill(i < 3 ? claude : .white.opacity(0.10))
                        .frame(width: 2, height: 12)
                }
            }
            .frame(width: 28, height: 14)
        case .telemetry:
            HistoryPreviewPath()
                .stroke(claude, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 16)
        }
    }
}

/// Static spark preview path — fixed shape so the tile reads consistently
/// across the picker, regardless of the user's actual usage trace.
private struct HistoryPreviewPath: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (0.00, 0.75), (0.16, 0.55),
            (0.34, 0.70), (0.50, 0.30),
            (0.69, 0.45), (0.84, 0.18),
            (1.00, 0.40)
        ]
        let points = pts.map { pt in
            CGPoint(x: rect.minX + rect.width * pt.0,
                    y: rect.minY + rect.height * pt.1)
        }
        return SparklinePath.line(through: points)
    }
}
