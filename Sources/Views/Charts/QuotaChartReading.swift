import SwiftUI
import AppKit

struct QuotaChartReading: Identifiable {
    let id: String
    let label: String
    let value: Double?
    let caption: String
    var amount: String? = nil
    var history: [Double] = []
}

struct QuotaValue: View {
    let reading: QuotaChartReading
    let mode: UsageDisplayMode
    var size: CGFloat = 21
    var weight: Font.Weight = .medium

    private var font: Font { .system(size: size, weight: weight, design: .monospaced) }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("100").font(font)
                Text("%").font(Typography.micro)
            }
            .hidden().accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if let value = reading.value {
                    Text("\(DisplayNumber.percent(value))")
                        .font(font)
                        .foregroundStyle(UrgencyColor.value(value, mode: mode))
                        .numericTransition(value: Double(DisplayNumber.percent(value)))
                } else {
                    Text(verbatim: reading.amount == nil ? "-" : "∞").font(font).foregroundStyle(.white.opacity(0.55))
                }
                Text("%")
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(reading.value == nil ? 0 : 1)
            }
        }
        .fixedSize()
    }
}

struct QuotaCaption: View {
    let caption: String

    var body: some View {
        Text(caption)
            .font(Typography.caption)
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(caption)
    }
}

struct QuotaAccessibility: ViewModifier {
    let reading: QuotaChartReading
    let mode: UsageDisplayMode

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.amount.map {
                L10n.tr("%@, %@ credits used, unlimited", reading.label, $0)
            } ?? reading.value.map {
                L10n.tr("%@, %d%%", reading.label, DisplayNumber.percent($0))
            } ?? L10n.tr("%@, no reading", reading.label))
            .accessibilityValue(reading.amount == nil ? L10n.tr(mode == .used ? "Used" : "Remaining") + ", " + reading.caption : reading.caption)
    }
}

enum QuotaPalette {
    static func shortTerm(_ color: Color) -> Color {
        if color == IslandColor.codex { return Color(red: 163/255, green: 163/255, blue: 163/255) }
        if color == IslandColor.claude { return Color(red: 242/255, green: 196/255, blue: 150/255) }
        if color == IslandColor.grok { return Color(red: 0.65, green: 0.83, blue: 1) }
        let native = NSColor(color)
        return Color(nsColor: native.blended(withFraction: 0.55, of: .white) ?? native)
    }
}
