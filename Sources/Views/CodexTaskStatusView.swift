import SwiftUI

struct CodexTaskStatusView: View {
    @ObservedObject private var store = CodexTaskStatusStore.shared
    @State private var hovered = false

    var body: some View {
        Button {
            store.openThread()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    CodexTaskStatusGlyph(status: store.snapshot.status, size: 42)
                        .shadow(color: statusColor.opacity(0.28), radius: 7)

                    VStack(alignment: .leading, spacing: 3) {
                        if store.displayMode == .iconAndText {
                            Text(L10n.tr(store.snapshot.status.label))
                                .font(Typography.providerTitle)
                                .foregroundStyle(.white.opacity(0.94))
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            Text("Codex")
                                .font(Typography.providerTitle)
                                .foregroundStyle(.white.opacity(0.78))
                        }

                        if let updatedAt = store.snapshot.updatedAt {
                            Text(L10n.tr("Updated %@", relative(updatedAt)))
                                .font(Typography.caption)
                                .foregroundStyle(.white.opacity(0.38))
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(hovered ? 0.72 : 0.30))
                }

                statusRail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .background(statusColor.opacity(hovered ? 0.035 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .onHover { hovered = $0 }
        .help(L10n.tr("%@ — open in Codex", L10n.tr(store.snapshot.status.label)))
        .accessibilityLabel(L10n.tr("Codex status: %@", L10n.tr(store.snapshot.status.label)))
        .accessibilityHint(L10n.tr("Open this task in Codex"))
        .animation(.hoverFade, value: hovered)
        .animation(.strongEaseOut, value: store.snapshot)
        .animation(.strongEaseOut, value: store.displayMode)
    }

    private var statusRail: some View {
        HStack(spacing: 0) {
            ForEach(CodexTaskStatusStore.Status.allCases, id: \.rawValue) { status in
                CodexTaskStatusGlyph(
                    status: status,
                    size: 19,
                    showsBackground: status == store.snapshot.status
                )
                .opacity(status == store.snapshot.status ? 1 : 0.28)
                .frame(maxWidth: .infinity)
                .help(L10n.tr(status.label))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            Capsule()
                .fill(.black.opacity(0.22))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.055), lineWidth: 0.5)
                }
        }
        .accessibilityHidden(true)
    }

    private var statusColor: Color {
        CodexTaskStatusGlyph.color(for: store.snapshot.status)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func relative(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CodexTaskStatusGlyph: View {
    let status: CodexTaskStatusStore.Status
    let size: CGFloat
    var showsBackground = true

    var body: some View {
        ZStack {
            if showsBackground {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.30), color.opacity(0.09)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(color.opacity(0.32), lineWidth: 0.6)
                    }
            }
            Image(systemName: icon)
                .font(.system(
                    size: size * (showsBackground ? 0.41 : 0.82),
                    weight: .semibold
                ))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }

    static func color(for status: CodexTaskStatusStore.Status) -> Color {
        switch status {
        case .running: Color(red: 0.30, green: 0.70, blue: 1.0)
        case .waitingApproval: Color(red: 1.0, green: 0.72, blue: 0.24)
        case .idle: Color(red: 0.48, green: 0.78, blue: 1.0)
        case .cancelled: Color(red: 0.72, green: 0.62, blue: 0.48)
        case .error: Color(red: 1.0, green: 0.34, blue: 0.34)
        case .unavailable: Color(red: 0.55, green: 0.57, blue: 0.62)
        }
    }

    private var color: Color { Self.color(for: status) }

    private var icon: String {
        switch status {
        case .running: "bolt.fill"
        case .waitingApproval: "hand.raised.fill"
        case .idle: "moon.zzz.fill"
        case .cancelled: "xmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }
}
