import SwiftUI

struct CodexResetStatus: View {
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    @State private var showPopover = false
    @State private var badgeHovered = false
    @State private var popoverHovered = false
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        if shouldShowBadge {
            badge
                .overlay(alignment: .topTrailing) {
                    if showPopover {
                        popover
                            .offset(x: 42, y: popoverYOffset)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
                    }
                }
                .zIndex(showPopover ? 10 : 0)
        }
    }

    private var shouldShowBadge: Bool {
        visibility.codexVisible && usageStore.codexResetCredits.availableCount > 0
            && !usageStore.codexResetCredits.availableCredits.isEmpty
    }

    private var badge: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(badgeHovered || showPopover ? 0.84 : 0.72))
            Text(resetAvailabilityText)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(badgeHovered || showPopover ? 0.96 : 0.86))
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovered in
            badgeHovered = hovered
            hovered ? presentPopover() : scheduleHide()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resetAvailabilityAccessibilityLabel)
        .accessibilityHint(L10n.tr("Hover to show reset expiration details"))
        .animation(.easeOut(duration: 0.12), value: badgeHovered)
        .animation(.strongEaseOut, value: showPopover)
    }

    private var resetAvailabilityText: String {
        let count = usageStore.codexResetCredits.availableCount
        return count == 1 ? L10n.tr("1 reset available") : L10n.tr("%d resets available", count)
    }

    private var resetAvailabilityAccessibilityLabel: String {
        let count = usageStore.codexResetCredits.availableCount
        return count == 1 ? L10n.tr("1 Codex reset available") : L10n.tr("%d Codex resets available", count)
    }

    private var popoverYOffset: CGFloat {
        usageStore.codexResetCredits.availableCredits.count == 1 ? -92 : -118
    }

    private var popover: some View {
        VStack(spacing: 6) {
            ForEach(Array(usageStore.codexResetCredits.availableCredits.prefix(3)), id: \.id) { credit in
                resetRow(credit)
            }
        }
        .padding(5)
        .frame(width: 330, alignment: .leading)
        .background(alignment: .top) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.17, green: 0.20, blue: 0.28).opacity(0.92))
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.75)
            }
        }
        .shadow(color: .black.opacity(0.42), radius: 28, y: 14)
        .shadow(color: Color.white.opacity(0.03), radius: 4)
        .onHover { hovered in
            popoverHovered = hovered
            hovered ? cancelHide() : scheduleHide()
        }
    }

    private func resetRow(_ credit: CodexResetCredit) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.43, green: 0.95, blue: 0.74))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("EXPIRES")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(.white.opacity(0.52))
                Text(absolute(credit.expiresAt))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .layoutPriority(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)

            Text(L10n.tr("Available"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.52, green: 0.95, blue: 0.71))
                .frame(width: 68, height: 26)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 0.29, green: 0.55, blue: 0.42).opacity(0.26))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(red: 0.37, green: 0.83, blue: 0.60).opacity(0.28), lineWidth: 0.75)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(red: 0.25, green: 0.62, blue: 0.42).opacity(0.18), lineWidth: 0.75)
                )
        )
    }

    private func presentPopover() {
        cancelHide()
        withAnimation(.strongEaseOut) {
            showPopover = true
        }
    }

    private func scheduleHide() {
        cancelHide()
        let workItem = DispatchWorkItem {
            if !badgeHovered && !popoverHovered {
                withAnimation(.easeOut(duration: 0.14)) {
                    showPopover = false
                }
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMdahmm")
        return formatter
    }()

    private func relative(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func absolute(_ date: Date) -> String {
        Self.absoluteFormatter.locale = L10n.locale
        return Self.absoluteFormatter.string(from: date)
    }
}
