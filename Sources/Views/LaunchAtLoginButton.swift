import SwiftUI

struct LaunchAtLoginButton: View {
    @ObservedObject private var store = LaunchAtLoginStore.shared
    @State private var hovered = false

    var body: some View {
        Button {
            store.toggle()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            .foregroundStyle(foreground)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .background {
                    Circle()
                        .fill(.white.opacity(hovered ? 0.08 : 0))
                }
                .overlay(alignment: .bottomTrailing) {
                    if store.isEnabled || store.errorMessage != nil {
                        Circle()
                            .fill(store.errorMessage == nil ? IslandColor.liveTeal : UrgencyColor.red)
                            .frame(width: 5, height: 5)
                            .offset(x: -4, y: -4)
                    }
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(helpText)
        .animation(.strongEaseOut, value: hovered)
        .animation(.strongEaseOut, value: store.isEnabled)
        .onAppear { store.refresh() }
    }

    private var iconName: String {
        store.isEnabled ? "power.circle.fill" : "power.circle"
    }

    private var foreground: Color {
        if store.errorMessage != nil { return UrgencyColor.red }
        if store.isEnabled { return IslandColor.liveTeal.opacity(hovered ? 0.90 : 0.68) }
        return .white.opacity(hovered ? 0.64 : 0.34)
    }

    private var helpText: String {
        if let error = store.errorMessage {
            return "Launch at login failed: \(error)"
        }
        return store.isEnabled ? "Launch at login: on" : "Launch at login: off"
    }
}
