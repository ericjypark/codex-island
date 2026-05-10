import SwiftUI

/// Provider titles row — Claude on the left, Codex on the right, with a
/// notch-width spacer in the middle that hides the title content behind
/// the physical notch. Lives outside `PagedContent` so it stays fixed
/// while the data area swipes between usage/cost screens.
///
/// Plan tags ("MAX" / "PLUS") are sourced from `UsageStore` since the
/// subscription tier is a property of the account, not the current page.
struct PanelHeader: View {
    let notch: NotchInfo
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usageStore = UsageStore.shared

    var body: some View {
        HStack(spacing: 0) {
            let claudeOn = visibility.claudeVisible
            let codexOn = visibility.codexVisible
            let geminiOn = visibility.geminiVisible

            HStack(spacing: 0) {
                providerTitle(name: "Claude", tag: usageStore.claude.plan?.uppercased(),
                              color: IslandColor.claude, alignment: .leading)
                    .opacity(claudeOn ? 1 : 0)
                    .animation(.openMorph, value: claudeOn)
                    .accessibilityHidden(!claudeOn)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notch.width)

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                providerTitle(name: "Codex", tag: usageStore.codex.plan?.uppercased(),
                              color: IslandColor.codex, alignment: .trailing)
                    .opacity(codexOn ? 1 : 0)
                    .animation(.openMorph, value: codexOn)
                    .accessibilityHidden(!codexOn)
                providerTitle(name: "Gemini", tag: usageStore.gemini.plan?.uppercased(),
                              color: IslandColor.gemini, alignment: .trailing)
                    .opacity(geminiOn ? 1 : 0)
                    .animation(.openMorph, value: geminiOn)
                    .accessibilityHidden(!geminiOn)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 22)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, max(0, notch.height - 22 - 4))
    }

    @ViewBuilder
    private func providerTitle(
        name: String,
        tag: String?,
        color: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        // Push past where the overlay logo lands: 9 leading + 20 logo + 8 gap.
        // For Gemini, we don't have a logo overlay in the root view yet,
        // so we don't need the offset (or we'll add it later).
        let logoOffset: CGFloat = (name == "Claude" || name == "Codex") ? 9 + 20 + 8 : 0

        HStack(spacing: 8) {
            Text(name)
                .font(Typography.providerTitle)
                .foregroundStyle(.white)
            if let tag {
                Text(tag)
                    .font(Typography.chip)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )
            }
        }
        .padding(alignment == .leading ? .leading : .trailing, logoOffset)
    }
}
