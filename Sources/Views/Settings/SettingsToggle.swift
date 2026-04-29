import SwiftUI

/// The on/off switch shared by every Settings row. Cobalt-glow track when
/// on, dim white-on-dark when off — same vocabulary as `LiveDot` so the
/// chrome reads as one product.
struct SettingsToggle: View {
    let isOn: Bool
    let action: () -> Void

    @State private var hovered = false
    private let trackWidth: CGFloat = 30
    private let trackHeight: CGFloat = 17
    private let dotSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .strokeBorder(.white.opacity(hovered ? 0.20 : 0.13), lineWidth: 1)
                    .background {
                        Capsule().fill(isOn
                            ? IslandColor.cobalt.opacity(0.32)
                            : .white.opacity(0.07))
                    }
                    .frame(width: trackWidth, height: trackHeight)

                Circle()
                    .fill(isOn ? IslandColor.cobalt : Color.white.opacity(0.5))
                    .frame(width: dotSize, height: dotSize)
                    .shadow(
                        color: isOn ? IslandColor.cobalt.opacity(0.85) : .clear,
                        radius: 5
                    )
                    .padding(.horizontal, (trackHeight - dotSize) / 2)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isOn)
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}
