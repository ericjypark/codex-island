import SwiftUI
import AppKit

/// Settings window — three tabs (General / Display / Providers) sandwiched
/// between a fixed brand header on top and the version/links/Quit footer
/// on the bottom. Tabs let each topical group stay short enough to fit a
/// modest window without scrolling, and the window itself is now resizable
/// rather than locked at 480×720, so the user controls the visible space.
struct SettingsView: View {
    @ObservedObject private var launchStore = LaunchAtLoginStore.shared
    @ObservedObject private var stylePref = StylePref.shared
    @ObservedObject private var costStylePref = CostStylePref.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var refreshStore = RefreshIntervalStore.shared
    @ObservedObject private var usage = UsageStore.shared
    @ObservedObject private var cost = CostStore.shared
    @ObservedObject private var updater = UpdaterController.shared

    @AppStorage("Settings.activeTab") private var activeTabRaw: String = SettingsTab.general.rawValue

    private var activeTab: SettingsTab {
        get { SettingsTab(rawValue: activeTabRaw) ?? .general }
        nonmutating set { activeTabRaw = newValue.rawValue }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic-light gutter — empty by design. Window has transparent
            // title bar so traffic lights float over the dark fill.
            Color.clear.frame(height: 28)

            BrandHeader(version: version)

            tabBar

            hairline

            // ScrollView guarantees the footer stays at the bottom of the
            // window regardless of how much content the active tab has —
            // overflow scrolls instead of pushing chrome off-screen.
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch activeTab {
                    case .general:   generalTab
                    case .display:   displayTab
                    case .providers: providersTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            hairline

            SettingsFooter(version: version)
        }
        .frame(minWidth: 440, minHeight: 420)
        .background(Color(red: 0.020, green: 0.020, blue: 0.027))
        .preferredColorScheme(.dark)
    }

    // MARK: - Tabs

    enum SettingsTab: String, CaseIterable {
        case general, display, providers

        var label: String {
            switch self {
            case .general:   "General"
            case .display:   "Display"
            case .providers: "Providers"
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func tabButton(_ tab: SettingsTab) -> some View {
        let isOn = (activeTab == tab)
        Button {
            activeTab = tab
        } label: {
            Text(tab.label)
                .font(Typography.tabLabel)
                .foregroundStyle(isOn
                    ? .white.opacity(0.95)
                    : .white.opacity(0.50))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? .white.opacity(0.08) : .clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.white.opacity(isOn ? 0.08 : 0), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isOn)
    }

    // MARK: - Tab content

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            generalSection
            updatesSection
        }
    }

    private var displayTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            chartSection
            costStyleSection
        }
    }

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            providersSection
            costSection
        }
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
                .font(Typography.sectionLabel)
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.34))
            Spacer(minLength: 8)
            if let hint {
                Text(hint)
                    .font(Typography.micro)
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
                subtitle: "How often to refresh."
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
                subtitle: "Check for new versions in the background and notify you when one's available."
            ) {
                SettingsToggle(isOn: updater.automaticallyChecks) {
                    updater.automaticallyChecks.toggle()
                }
            }
            SettingsRow(
                title: "Check now",
                subtitle: "Look for a new version immediately."
            ) {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Text("Check")
                        .font(Typography.button)
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
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    /// Single-row Cost section. Re-uses the section-label typography on the
    /// left and inlines the freshness caption + refresh button on the right
    /// — compact so it sits cleanly under the Providers list.
    private var costSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Cost")
                .font(Typography.sectionLabel)
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.34))

            Text(costSubtitle())
                .font(Typography.label)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                cost.refresh()
            } label: {
                Text(cost.loading ? "Refreshing…" : "Refresh")
                    .font(Typography.button)
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
        .padding(.bottom, 14)
    }

    /// Days past the embedded pricing snapshot before the Cost section
    /// admits the data may be stale. Anthropic re-tiered Opus once already,
    /// so two months without a refresh is the point where dollar totals
    /// could meaningfully drift from reality.
    private static let pricingFreshnessThreshold = 60

    private func costSubtitle() -> String {
        let base: String
        if cost.loading {
            base = "scanning local logs…"
        } else if let updated = cost.lastUpdated {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            base = "last scan \(f.localizedString(for: updated, relativeTo: Date()))"
        } else {
            base = "swipe panel to view"
        }
        let days = Pricing.daysSinceSnapshot
        if days > Self.pricingFreshnessThreshold {
            return base + " · pricing data \(days)d old"
        }
        return base
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Chart style", hint: "⌘-click to cycle")
            ChartStylePicker(selected: $stylePref.style)
                .padding(.top, 4)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var costStyleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Cost view", hint: "⌘-click to cycle")
            CostStylePicker(selected: $costStylePref.style)
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
                        .font(Typography.bodyNumber)
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
