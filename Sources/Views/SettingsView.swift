import SwiftUI
import AppKit

/// Settings window content. Composed of six zones:
///   1. Brand header — notch silhouette + name + tagline + version pill
///   2. General — Launch at Login, Refresh interval
///   3. Providers — Claude / Codex per-provider visibility
///   4. Default chart — 5-tile picker (replaces the buried ⌘-click cycle)
///   5. Footer — version + GitHub + License + Quit
///
/// All sections sit on the same near-black surface (#050507) and are
/// separated by hairline gradient dividers. No bordered cards — rows lift
/// to a faint white wash on hover instead.
struct SettingsView: View {
    @ObservedObject private var launchStore = LaunchAtLoginStore.shared
    @ObservedObject private var stylePref = StylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var refreshStore = RefreshIntervalStore.shared
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var cost = CostStore.shared
    @ObservedObject private var updater = UpdaterController.shared

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic-light gutter — empty by design. Window has transparent
            // title bar so traffic lights float over the dark fill.
            Color.clear.frame(height: 28)

            BrandHeader(version: version)

            hairline

            generalSection
            updatesSection
            providersSection
            costSection
            chartSection

            Spacer(minLength: 0)

            hairline

            SettingsFooter(version: version)
        }
        .frame(width: 480, height: 720)
        .background(Color(red: 0.020, green: 0.020, blue: 0.027))
        .preferredColorScheme(.dark)
    }

    // MARK: - Pieces

    private var hairline: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.055), .white.opacity(0.055), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String, hint: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.34))
            Spacer(minLength: 8)
            if let hint {
                Text(hint)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.18))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Sections

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("General")
            SettingsRow(
                title: "Launch at Login",
                subtitle: launchStore.errorMessage ?? "Open CodexIsland when you sign in."
            ) {
                SettingsToggle(isOn: launchStore.isEnabled) { launchStore.toggle() }
            }
            SettingsRow(
                title: "Refresh interval",
                subtitle: "How often to re-check usage."
            ) {
                refreshSegmented
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Updates")
            SettingsRow(
                title: "Check for updates automatically",
                subtitle: "Sparkle checks the appcast in the background and prompts you when a new version ships."
            ) {
                SettingsToggle(isOn: updater.automaticallyChecks) {
                    updater.automaticallyChecks.toggle()
                }
            }
            SettingsRow(
                title: "Check now",
                subtitle: "Look for a new version right now."
            ) {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Text("Check")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white.opacity(0.10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Providers")
            SettingsRow(
                title: "Claude",
                subtitle: providerSubtitle(usage.claude),
                dot: IslandColor.claude,
                chip: usage.claude.plan?.uppercased()
            ) {
                SettingsToggle(isOn: visibility.claudeVisible) {
                    visibility.claudeVisible.toggle()
                }
            }
            SettingsRow(
                title: "Codex",
                subtitle: providerSubtitle(usage.codex),
                dot: IslandColor.codex,
                chip: usage.codex.plan?.uppercased()
            ) {
                SettingsToggle(isOn: visibility.codexVisible) {
                    visibility.codexVisible.toggle()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// Single-row Cost section. Re-uses the section-label typography on the
    /// left so it visually rhymes with the other section headers, but
    /// inlines the freshness caption + refresh button on the right instead
    /// of stacking a SettingsRow underneath. Saves ~70pt vs the expanded
    /// section pattern, which keeps SettingsFooter on screen at 720pt.
    private var costSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Cost")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.34))

            Text(costSubtitle())
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                cost.refresh()
            } label: {
                Text(cost.loading ? "Refreshing…" : "Refresh")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                            }
                    }
            }
            .buttonStyle(.plain)
            .disabled(cost.loading)
            .opacity(cost.loading ? 0.55 : 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func costSubtitle() -> String {
        if cost.loading { return "scanning local logs…" }
        guard let updated = cost.lastUpdated else { return "swipe panel to view" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return "Last scan \(f.localizedString(for: updated, relativeTo: Date()))"
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Default chart", hint: "⌘-click in panel to cycle")
            ChartStylePicker(selected: $stylePref.style)
                .padding(.top, 4)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // MARK: - Refresh segmented

    private var refreshSegmented: some View {
        HStack(spacing: 0) {
            ForEach(RefreshIntervalStore.allowed, id: \.self) { value in
                let isOn = (value == refreshStore.seconds)
                Button {
                    refreshStore.seconds = value
                } label: {
                    Text(label(for: value))
                        .font(.system(size: 11, weight: .semibold).monospaced())
                        .foregroundStyle(isOn
                            ? Color.white.opacity(0.95)
                            : .white.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isOn ? .white.opacity(0.10) : .clear)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(.white.opacity(isOn ? 0.08 : 0), lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.04))
        }
    }

    private func label(for seconds: Int) -> String {
        switch seconds {
        case 300: return "5m"
        case 900: return "15m"
        case 1800: return "30m"
        default: return "\(seconds)s"
        }
    }

    // MARK: - Subtitle composition

    private func providerSubtitle(_ u: AppUsage) -> String {
        let synced: String = {
            guard let updated = usage.lastUpdated else { return "idle" }
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return "synced \(f.localizedString(for: updated, relativeTo: Date()))"
        }()
        let nums = "\(Int(u.fiveHour.usedPercent * 100))% / \(Int(u.weekly.usedPercent * 100))%"
        return "\(synced) · \(nums)"
    }
}
