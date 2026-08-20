import SwiftUI
import AppKit

/// Bottom-left of the expanded panel: gear glyph that opens the Settings
/// window via our hand-rolled SettingsWindowController. Replaces the older
/// LaunchAtLoginButton — the toggle now lives inside Settings so the panel
/// corner is no longer two near-identical power glyphs.
struct SettingsButton: View {
    @State private var hovered = false

    var body: some View {
        Button {
            SettingsWindowController.shared.show()
        } label: {
            Image(systemName: "gearshape")
                .font(Typography.button)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.primary.opacity(hovered ? 0.64 : 0.34))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .background {
                    Circle()
                        .fill(Color.primary.opacity(hovered ? 0.08 : 0))
                }
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovered = $0 }
        .help(L10n.tr("Settings"))
        .animation(.hoverFade, value: hovered)
        .accessibilityLabel(L10n.tr("Settings"))
    }
}
