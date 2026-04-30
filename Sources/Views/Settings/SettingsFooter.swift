import SwiftUI
import AppKit

/// Bottom footer for the Settings window. Version flush left, GitHub /
/// License as dotted-underline links, Quit pill flush right.
struct SettingsFooter: View {
    let version: String

    @State private var quitHovered = false

    private static let githubURL = URL(string: "https://github.com/ericjypark/codex-island")!
    private static let licenseURL = URL(string: "https://github.com/ericjypark/codex-island/blob/main/LICENSE")!

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(version)
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.34))

            link("GitHub", url: Self.githubURL)
            link("License", url: Self.licenseURL)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(quitHovered ? 0.92 : 0.55))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(quitHovered ? 0.06 : 0.03))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
                            }
                    }
            }
            .buttonStyle(.plain)
            .onHover { quitHovered = $0 }
            .help("Quit CodexIsland")
            .animation(.strongEaseOut, value: quitHovered)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func link(_ title: String, url: URL) -> some View {
        DottedLink(title: title) {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct DottedLink: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Typography.label)
                    .foregroundStyle(.white.opacity(hovered ? 0.92 : 0.55))
                Text("↗")
                    .font(Typography.micro)
                    .foregroundStyle(.white.opacity(hovered ? 0.6 : 0.3))
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(hovered ? 0.32 : 0.18))
                    .frame(height: 0.5)
                    .offset(y: 1)
                    .mask(
                        // Dotted via repeating gradient
                        LinearGradient(
                            colors: [.black, .clear, .black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.10), value: hovered)
    }
}
