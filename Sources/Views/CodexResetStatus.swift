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
                            // Anchored to the badge top, dropped clear of the
                            // badge so the card grows downward into the panel.
                            // The badge now lives in the header (panel top), so
                            // opening upward would spill off the top edge.
                            .offset(y: 28)
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
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
                .font(Typography.caption)
                .foregroundStyle(IslandColor.codex.opacity(badgeHovered || showPopover ? 1 : 0.8))
            Text(resetAvailabilityText)
                .font(Typography.caption)
                .foregroundStyle(.white.opacity(badgeHovered || showPopover ? 0.85 : 0.55))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(.white.opacity(badgeHovered || showPopover ? 0.05 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .onHover { hovered in
            badgeHovered = hovered
            hovered ? presentPopover() : scheduleHide()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resetAvailabilityAccessibilityLabel)
        .accessibilityHint(L10n.tr("Hover to show reset expiration details"))
        .animation(.hoverFade, value: badgeHovered)
        .animation(.hoverFade, value: showPopover)
    }

    private var resetAvailabilityText: String {
        // Short form: the badge now sits next to the Codex title where
        // "N resets available" truncates. The fuller phrasing lives on the
        // accessibility label below.
        let count = usageStore.codexResetCredits.availableCount
        return count == 1 ? L10n.tr("1 reset") : L10n.tr("%d resets", count)
    }

    private var resetAvailabilityAccessibilityLabel: String {
        let count = usageStore.codexResetCredits.availableCount
        return count == 1 ? L10n.tr("1 Codex reset available") : L10n.tr("%d Codex resets available", count)
    }

    private var popover: some View {
        VStack(spacing: 4) {
            ForEach(Array(usageStore.codexResetCredits.availableCredits.prefix(3)), id: \.id) { credit in
                resetRow(credit)
            }
        }
        .padding(6)
        .frame(width: 210, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        .onHover { hovered in
            popoverHovered = hovered
            hovered ? cancelHide() : scheduleHide()
        }
    }

    private func resetRow(_ credit: CodexResetCredit) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.counterclockwise")
                .font(Typography.caption)
                .foregroundStyle(IslandColor.codex.opacity(0.9))

            Text(L10n.tr("EXPIRES"))
                .font(Typography.sectionLabel)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.40))
            Spacer(minLength: 8)

            Text(absolute(credit.expiresAt))
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.05))
        )
    }

    /// Popover-tier timing: same strong ease-out curve as the rest of the
    /// app, but faster than `.strongEaseOut` (280ms) — a small hover
    /// reveal should settle in under 200ms. Exit is faster than enter.
    private static let popoverIn = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
    private static let popoverOut = Animation.easeOut(duration: 0.09)

    private func presentPopover() {
        cancelHide()
        withAnimation(Self.popoverIn) {
            showPopover = true
        }
    }

    private func scheduleHide() {
        cancelHide()
        let workItem = DispatchWorkItem {
            if !badgeHovered && !popoverHovered {
                withAnimation(Self.popoverOut) {
                    showPopover = false
                }
            }
        }
        hideWorkItem = workItem
        // Just enough grace to cross the badge → popover gap; any longer
        // and the card lingers after hover-out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()

    private func absolute(_ date: Date) -> String {
        Self.absoluteFormatter.locale = L10n.locale
        return Self.absoluteFormatter.string(from: date)
    }
}
