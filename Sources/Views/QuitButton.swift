import SwiftUI
import AppKit

/// Bottom-right corner of the expanded panel: a small power glyph that
/// terminates the app. Lives as an .overlay(alignment: .bottomTrailing)
/// on IslandRootView so it lands at the literal panel corner instead of
/// being crowded into the footer beside the live status text.
struct QuitButton: View {
    @State private var hovered = false

    var body: some View {
        Image(systemName: "power")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(hovered ? 0.85 : 0.42))
            .padding(8)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onTapGesture { NSApp.terminate(nil) }
            .help("Quit CodexIsland")
            .animation(.strongEaseOut, value: hovered)
    }
}
