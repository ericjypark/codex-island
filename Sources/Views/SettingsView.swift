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
    @ObservedObject private var tokenMode = TokenCountModeStore.shared
    @ObservedObject private var lowPower = LowPowerModeStore.shared
    @ObservedObject private var alertPrefs = AlertThresholdStore.shared
    @ObservedObject private var spacing = IslandSpacingStore.shared
    @ObservedObject private var targetDisplay = IslandTargetDisplayStore.shared
    @ObservedObject private var appLanguage = AppLanguageStore.shared
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

            SettingsFooter()
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
            Text(L10n.tr(tab.label))
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
        .accessibilityLabel(L10n.tr("%@ tab", L10n.tr(tab.label)))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Tab content

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            generalSection
            alertsSection
            updatesSection
        }
    }

    private var displayTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            chartSection
            costStyleSection
            targetDisplaySection
            if spacingSectionVisible {
                spacingSection
            }
        }
    }

    /// Shown when the island is currently rendered on a non-notched
    /// display (whether by Auto or by an explicit user pick of an
    /// external). Reads the same resolver the window controller uses, so
    /// the gate stays in sync with where the island actually is.
    private var spacingSectionVisible: Bool {
        DisplayInfo.currentTarget()?.notch.hasNotch == false
    }

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            providersSection
            tokenCountingSection
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
            Text(L10n.tr(text))
                .font(Typography.sectionLabel)
                .tracking(1.05)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.34))
            Spacer(minLength: 8)
            if let hint {
                Text(L10n.tr(hint))
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
            SettingsRow(
                title: "Language",
                subtitle: appLanguage.language.subtitle
            ) {
                languagePicker
            }
            SettingsRow(
                title: "Low Power Mode",
                subtitle: "Glow only on refresh, hover, or limit alerts."
            ) {
                SettingsToggle(isOn: lowPower.enabled) {
                    lowPower.enabled.toggle()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    /// Approaching-limit alerts. Default off — opt-in via the toggle.
    /// When on, the silhouette glow tints amber/red while a tracked 5h
    /// window is at or above the configured percentages, and the peek
    /// pill auto-extends once when a window first crosses each threshold.
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Alerts")
            SettingsRow(
                title: "Approaching-limit alerts",
                subtitle: "Tint the island and pulse the peek pill when 5-hour usage nears your limit."
            ) {
                SettingsToggle(isOn: alertPrefs.enabled) {
                    // withAnimation here so the threshold rows + Preview row
                    // crossfade their disabled/enabled state instead of
                    // snapping. The dim/undim is the user's signal that the
                    // controls became interactive.
                    withAnimation(.strongEaseOut) {
                        alertPrefs.enabled.toggle()
                    }
                }
            }
            thresholdsBlock
                .disabled(!alertPrefs.enabled)
                .opacity(alertPrefs.enabled ? 1.0 : 0.40)
            if alertPrefs.enabled && isDevMode {
                SettingsRow(
                    title: "Preview",
                    subtitle: "Inject test percentages. Visible only when launched with CODEXISLAND_DEBUG=1."
                ) {
                    previewButtons
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var previewButtons: some View {
        HStack(spacing: 4) {
            previewButton("Live") { usage.refresh() }
                .keyboardShortcut("1", modifiers: .command)
                .help("⌘1 — pull real provider data")
            previewButton("Warn") { runPreview(claude: 0.85, codex: 0.55) }
                .keyboardShortcut("2", modifiers: .command)
                .help("⌘2 — Claude 85%, Codex 55%")
            previewButton("Crit") { runPreview(claude: 0.96, codex: 0.55) }
                .keyboardShortcut("3", modifiers: .command)
                .help("⌘3 — Claude 96%, Codex 55%")
            previewButton("Both") { runPreview(claude: 0.86, codex: 0.97) }
                .keyboardShortcut("4", modifiers: .command)
                .help("⌘4 — Claude 86%, Codex 97%")
        }
    }

    @ViewBuilder
    private func previewButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L10n.tr(label))
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.white.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var isDevMode: Bool {
        AppEnvironment.isDebug
    }

    /// Resets the engine's crossing memory before injecting so each click
    /// fires a fresh pulse — otherwise the second "Warn" click would be a
    /// no-op (key already in memory from the first click).
    private func runPreview(claude: Double, codex: Double) {
        AlertEngine.shared.prepareForPreview()
        usage.injectPreviewUsage(claudeFiveHour: claude, codexFiveHour: codex)
    }

    /// Single paired block listing both thresholds inline, each tagged
    /// with its own colored dot so the visual mapping (amber → warning,
    /// red → critical) reads at a glance. Replaces what used to be two
    /// near-duplicate SettingsRows whose subtitles only differed by one
    /// word.
    private var thresholdsBlock: some View {
        VStack(spacing: 6) {
            thresholdLine(
                color: IslandColor.alertAmber,
                label: "Warning",
                value: Binding(
                    get: { alertPrefs.warningPercent },
                    set: { alertPrefs.warningPercent = $0 }
                ),
                range: warningStepperRange
            )
            thresholdLine(
                color: IslandColor.alertRed,
                label: "Critical",
                value: Binding(
                    get: { alertPrefs.criticalPercent },
                    set: { alertPrefs.criticalPercent = $0 }
                ),
                range: criticalStepperRange
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func thresholdLine(
        color: Color,
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.7), radius: 4)
                .accessibilityHidden(true)
            Text(L10n.tr(label))
                .font(Typography.rowTitle)
                .tracking(-0.07)
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 8)
            thresholdStepper(value: value, range: range)
        }
        .padding(.vertical, 5)
    }

    /// Warning's upper bound is `critical - 1` so the steppers can't drift
    /// the pair into an invalid state. Same idea in reverse for critical.
    private var warningStepperRange: ClosedRange<Int> {
        let lo = AlertThresholdStore.warningRange.lowerBound
        let hi = min(AlertThresholdStore.warningRange.upperBound, alertPrefs.criticalPercent - 1)
        return lo...max(lo, hi)
    }

    private var criticalStepperRange: ClosedRange<Int> {
        let lo = max(AlertThresholdStore.criticalRange.lowerBound, alertPrefs.warningPercent + 1)
        let hi = AlertThresholdStore.criticalRange.upperBound
        return min(lo, hi)...hi
    }

    @ViewBuilder
    private func thresholdStepper(
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        // Wrapped binding clamps anything the user types so out-of-range
        // direct entry (e.g. "999") snaps to the dynamic range on commit.
        // The dynamic range already enforces `warning < critical`, so this
        // also covers the cross-field constraint without a separate check.
        let clamped = Binding<Int>(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = max(range.lowerBound, min(range.upperBound, newValue))
            }
        )
        HStack(spacing: 3) {
            TextField("", value: clamped, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.95))
                .monospacedDigit()
                .frame(width: 22, height: 18)
                .clipped()
            Text("%")
                .font(Typography.bodyNumber)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(width: 64, height: 28)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                }
        }
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
                PillButton(label: "Check") { updater.checkForUpdates() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var languagePicker: some View {
        Picker("", selection: languageSelection) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Text(language.menuLabel).tag(language)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220)
        .accessibilityLabel(L10n.tr("Language"))
    }

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { appLanguage.language },
            set: { newLanguage in
                if appLanguage.select(newLanguage) {
                    showLanguageRestartPrompt()
                }
            }
        )
    }

    private func showLanguageRestartPrompt() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Restart CodexIsland to apply language?")
        alert.informativeText = L10n.tr("Your language change will take effect after CodexIsland restarts.")
        alert.addButton(withTitle: L10n.tr("Restart now"))
        alert.addButton(withTitle: L10n.tr("Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            appLanguage.restartApp()
        }
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
                    withAnimation(.openMorph) {
                        visibility.claudeVisible.toggle()
                    }
                }
            }
            SettingsRow(
                title: "Codex",
                subtitle: providerSubtitle(usage.codex),
                dot: IslandColor.codex,
                chip: usage.codex.plan?.uppercased()
            ) {
                SettingsToggle(isOn: visibility.codexVisible) {
                    withAnimation(.openMorph) {
                        visibility.codexVisible.toggle()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    /// Lets the user pick which token total drives the TOKENS hero on the
    /// cost screen. Anthropic's claude.ai stats panel reports input + output
    /// only; ccusage (and our default) sums every token type that crossed
    /// the wire — the two diverge by ~10× because cache_read_input_tokens
    /// dominates Claude Code workflows. Both totals are computed every
    /// scan, so flipping this is instant — no rescan.
    private var tokenCountingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Tokens")
            SettingsRow(
                title: "Token counting",
                subtitle: tokenModeSubtitle
            ) {
                tokenModeSegmented
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var tokenModeSubtitle: String {
        switch tokenMode.mode {
        case .all:
            return L10n.tr("Counts everything — input, output, and cache. Mirrors ccusage.")
        case .billable:
            return L10n.tr("Input + output only. Matches Anthropic's claude.ai stats.")
        }
    }

    private var tokenModeSegmented: some View {
        SegmentedControl(
            items: TokenCountMode.allCases,
            selected: $tokenMode.mode,
            label: { $0.label },
            accessibilityPrefix: "Token counting"
        )
    }

    /// Single-row Cost section. Re-uses the section-label typography on the
    /// left and inlines the freshness caption + refresh button on the right
    /// — compact so it sits cleanly under the Providers list.
    private var costSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(L10n.tr("Cost"))
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

            PillButton(
                label: cost.loading ? "Refreshing…" : "Refresh",
                isLoading: cost.loading
            ) { cost.refresh() }
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = L10n.locale
        f.unitsStyle = .abbreviated
        return f
    }()

    private func costSubtitle() -> String {
        let days = Pricing.daysSinceSnapshot
        let isStale = days > Self.pricingFreshnessThreshold

        if cost.loading {
            return isStale
                ? L10n.tr("scanning local logs… · pricing data %dd old", days)
                : L10n.tr("scanning local logs…")
        } else if let updated = cost.lastUpdated {
            let relative = Self.relativeFormatter.localizedString(for: updated, relativeTo: Date())
            return isStale
                ? L10n.tr("last scan %@ · pricing data %dd old", relative, days)
                : L10n.tr("last scan %@", relative)
        }

        return isStale
            ? L10n.tr("swipe panel to view · pricing data %dd old", days)
            : L10n.tr("swipe panel to view")
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

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Spacing")
            SettingsRow(
                title: "Island width",
                subtitle: "Tightens the gap between logos when the island is on a screen without a hardware notch."
            ) {
                spacingSegmented
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    /// Default-on-the-left: Compact is the new default, so it sits left
    /// of Notch-style.
    private var spacingSegmented: some View {
        SegmentedControl(
            items: [IslandSpacingStore.Mode.compact, .notchStyle],
            selected: $spacing.mode,
            label: { $0 == .compact ? "Compact" : "Notch-style" },
            accessibilityPrefix: "Island width"
        )
    }

    private var targetDisplaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Target Display")
            SettingsRow(
                title: "Show on",
                subtitle: targetDisplaySubtitle
            ) {
                targetDisplayPicker
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    /// Subtitle shows the resolved current display when the user is on
    /// `.auto` — answers "where is the island actually?" without making
    /// the user open another setting.
    private var targetDisplaySubtitle: String {
        switch targetDisplay.choice {
        case .auto:
            if let resolved = DisplayInfo.currentTarget() {
                return L10n.tr("Auto — currently on %@.", resolved.name)
            }
            return L10n.tr("Auto — picks a notched display when available.")
        case .stable:
            return L10n.tr("Pinned to a specific display. Falls back to Auto if unplugged.")
        }
    }

    private var targetDisplayPicker: some View {
        let displays = DisplayInfo.all()
        let autoTag = IslandTargetDisplayStore.Choice.auto.rawValue
        return Picker("", selection: pickerSelection) {
            Text(L10n.tr("Auto")).tag(autoTag)
            ForEach(displays, id: \.stableID) { d in
                Text(d.isBuiltin ? L10n.tr("%@ (built-in)", d.name) : d.name)
                    .tag(d.stableID)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220)
        .accessibilityLabel(L10n.tr("Target display"))
    }

    /// Bridges the enum `Choice` to a `String` selection that SwiftUI's
    /// `Picker` can use as tags.
    private var pickerSelection: Binding<String> {
        Binding(
            get: { targetDisplay.choice.rawValue },
            set: { newValue in
                targetDisplay.choice = IslandTargetDisplayStore.Choice(rawValue: newValue)
            }
        )
    }

    // MARK: - Refresh segmented

    private var refreshSegmented: some View {
        SegmentedControl(
            items: RefreshIntervalStore.allowed,
            selected: $refreshStore.seconds,
            label: { Self.label(for: $0) },
            accessibilityPrefix: "Refresh interval"
        )
    }

    private static func label(for seconds: Int) -> String {
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
            guard let updated = usage.lastUpdated else { return L10n.tr("idle") }
            return L10n.tr("synced %@", Self.relativeFormatter.localizedString(for: updated, relativeTo: Date()))
        }()
        let nums = "\(Self.windowCaption(u.fiveHour)) / \(Self.windowCaption(u.weekly))"
        return "\(synced) · \(nums)"
    }

    private static func windowCaption(_ w: WindowUsage) -> String {
        if let err = w.error, w.percentInt == 0 { return "⚠ \(err)" }
        return "\(w.percentInt)%"
    }
}
