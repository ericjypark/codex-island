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
        let visible = visibleProviders()

        HStack(spacing: 0) {
            if visible.isEmpty {
                Spacer()
            } else if visible.count == 1 {
                let p = visible[0]
                providerTitle(name: p.name, tag: p.tag, color: p.color)
                    .frame(maxWidth: .infinity)
                // When 1 provider, UsageView shows the chart on the left
                // and breakdown on the right. We center the title over
                // the chart half to align with it.
                Spacer()
            } else {
                ForEach(visible, id: \.provider) { p in
                    providerTitle(name: p.name, tag: p.tag, color: p.color)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 22)
        // Push the entire header below the hardware notch so the center title is visible.
        .padding(.top, max(0, notch.height) + 4)
        .padding(.bottom, 8)
    }

    private struct VisibleHeaderProvider {
        let provider: AlertEngine.Provider
        let name: String
        let tag: String?
        let color: Color
    }

    private func visibleProviders() -> [VisibleHeaderProvider] {
        var out: [VisibleHeaderProvider] = []
        if visibility.claudeVisible {
            out.append(VisibleHeaderProvider(provider: .claude, name: "Claude", tag: usageStore.claude.plan?.uppercased(), color: IslandColor.claude))
        }
        if visibility.codexVisible {
            out.append(VisibleHeaderProvider(provider: .codex, name: "Codex", tag: usageStore.codex.plan?.uppercased(), color: IslandColor.codex))
        }
        if visibility.geminiVisible {
            out.append(VisibleHeaderProvider(provider: .gemini, name: "Gemini", tag: usageStore.gemini.plan?.uppercased(), color: IslandColor.gemini))
        }
        return out
    }

    @ViewBuilder
    private func providerTitle(
        name: String,
        tag: String?,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(Typography.providerTitle)
                .foregroundStyle(.white)
            if let tag, !tag.isEmpty {
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
    }
}
