import SwiftUI

struct LaunchAtLoginButton: View {
    @ObservedObject private var store = LaunchAtLoginStore.shared
    @State private var hovered = false

    var body: some View {
        Button {
            store.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                Text("login")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(border, lineWidth: 0.5)
                    )
            )
            .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(helpText)
        .animation(.strongEaseOut, value: hovered)
        .animation(.strongEaseOut, value: store.isEnabled)
        .onAppear { store.refresh() }
    }

    private var foreground: Color {
        if store.errorMessage != nil { return UrgencyColor.red }
        if store.isEnabled { return IslandColor.liveTeal }
        return .white.opacity(hovered ? 0.70 : 0.46)
    }

    private var background: Color {
        if store.errorMessage != nil { return UrgencyColor.red.opacity(0.10) }
        if store.isEnabled { return IslandColor.liveTeal.opacity(0.12) }
        return .white.opacity(hovered ? 0.08 : 0.04)
    }

    private var border: Color {
        if store.errorMessage != nil { return UrgencyColor.red.opacity(0.35) }
        if store.isEnabled { return IslandColor.liveTeal.opacity(0.24) }
        return .white.opacity(hovered ? 0.14 : 0.07)
    }

    private var helpText: String {
        if let error = store.errorMessage {
            return "Launch at login failed: \(error)"
        }
        return store.isEnabled ? "Launch at login is on" : "Launch at login is off"
    }
}
