import SwiftUI
import AppKit

/// Opens Settings from the expanded panel footer.
struct SettingsButton: View {
    @State private var hovered = false

    var body: some View {
        Button {
            SettingsWindowController.shared.show()
        } label: {
            Image(systemName: "gearshape")
                .font(Typography.button)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(hovered ? 0.64 : 0.34))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .background {
                    Circle()
                        .fill(.white.opacity(hovered ? 0.08 : 0))
                }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovered = $0 }
        .help(L10n.tr("Settings"))
        .animation(.hoverFade, value: hovered)
        .accessibilityLabel(L10n.tr("Settings"))
    }
}
