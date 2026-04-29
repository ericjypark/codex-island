import SwiftUI

/// A single Settings list row. Title (+ optional inline brand dot and
/// MAX/PLUS chip), subtitle, and a trailing control. Hover lifts the
/// background to a faint white wash — the "I'm interactive" cue without
/// the bordered-card treatment.
struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let dot: Color?
    let chip: String?
    @ViewBuilder var trailing: () -> Trailing

    @State private var hovered = false

    init(
        title: String,
        subtitle: String? = nil,
        dot: Color? = nil,
        chip: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.dot = dot
        self.chip = chip
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let dot {
                        Circle()
                            .fill(dot)
                            .frame(width: 7, height: 7)
                            .shadow(color: dot.opacity(0.7), radius: 4)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    }
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .tracking(-0.07)
                        .foregroundStyle(.white.opacity(0.92))
                    if let chip {
                        Text(chip)
                            .font(.system(size: 9, weight: .bold).monospaced())
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white.opacity(0.06))
                            )
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(hovered ? 0.030 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.10), value: hovered)
    }
}
