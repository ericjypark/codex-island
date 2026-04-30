import SwiftUI
import AppKit

/// Cost screen — second page of the expanded panel. Mirrors `UsageView`'s
/// chrome (provider titles, hairline divider, footer with style chip + page
/// dots + sync status) but renders dollar spend instead of subscription %.
struct CostView: View {
    let notch: NotchInfo
    @ObservedObject private var store = CostStore.shared
    @ObservedObject private var pref = StylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var screenPref = ScreenPref.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                providerTitle(name: "Claude", tag: planTag(forClaude: true),
                              color: IslandColor.claude, alignment: .leading)
                    .opacity(visibility.claudeVisible ? 1 : 0.30)
                    .saturation(visibility.claudeVisible ? 1 : 0)
                Color.clear.frame(width: notch.width)
                providerTitle(name: "Codex", tag: planTag(forClaude: false),
                              color: IslandColor.codex, alignment: .trailing)
                    .opacity(visibility.codexVisible ? 1 : 0.30)
                    .saturation(visibility.codexVisible ? 1 : 0)
            }
            .frame(height: 22)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, max(0, notch.height - 22 - 4))

            HStack(spacing: 0) {
                CostBlock(
                    color: visibility.claudeVisible ? IslandColor.claude : .white.opacity(0.32),
                    cost: visibility.claudeVisible ? store.claude : .dummy
                )
                .opacity(visibility.claudeVisible ? 1 : 0.55)
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, .white.opacity(0.06), .clear],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 1)
                    .padding(.vertical, 8)
                CostBlock(
                    color: visibility.codexVisible ? IslandColor.codex : .white.opacity(0.32),
                    cost: visibility.codexVisible ? store.codex : .dummy
                )
                .opacity(visibility.codexVisible ? 1 : 0.55)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 6)

            LinearGradient(
                colors: [.clear, .white.opacity(0.06), .white.opacity(0.06), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 1)
            .padding(.horizontal, 22)

            HStack(spacing: 10) {
                // Mirror the position of UsageView's STEPPED chip with a USD
                // chip — the cost screen's bars are always stepped, so a
                // chart-style chip would mislead.
                Text("USD")
                    .font(.system(size: 9, weight: .bold).monospaced())
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                            )
                    )

                Spacer()

                PageIndicator(active: screenPref.screen)

                HStack(spacing: 6) {
                    LiveDot(active: store.lastUpdated != nil && !store.loading)
                    if store.loading {
                        Text("syncing…")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    } else if let updated = store.lastUpdated {
                        Text("synced")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(relative(updated))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.72))
                    } else {
                        Text("idle")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Plan tag pulled from the API-side UsageStore — same source as
    /// UsageView, since the subscription tier is independent of which page
    /// the user is on.
    private func planTag(forClaude: Bool) -> String? {
        let usage = forClaude ? UsageStore.shared.claude : UsageStore.shared.codex
        return usage.plan?.uppercased()
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    @ViewBuilder
    private func providerTitle(
        name: String,
        tag: String?,
        color: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        let logoOffset: CGFloat = 9 + 20 + 8

        let content = HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if let tag {
                Text(tag)
                    .font(.system(size: 9, weight: .bold).monospaced())
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

        if alignment == .leading {
            HStack {
                content.padding(.leading, logoOffset)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack {
                Spacer(minLength: 0)
                content.padding(.trailing, logoOffset)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
