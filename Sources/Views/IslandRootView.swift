import SwiftUI
import AppKit

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @State private var hovering = false
    @State private var contentVisible = false
    @State private var pillsVisible = false
    @State private var pulseToken = UUID()

    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var screenPref = ScreenPref.shared
    @ObservedObject private var stylePref = StylePref.shared
    @ObservedObject private var costStylePref = CostStylePref.shared

    /// PNG-from-disk decode is ~150µs per call. Computed properties
    /// re-decoded both logos every render — inside a 120Hz TimelineView
    /// that's 240 main-thread decodes/sec. Cache once on appear.
    @State private var claudeLogo: NSImage?
    @State private var openaiLogo: NSImage?
    @State private var geminiLogo: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Only the rotating loading sweep needs per-frame re-renders
            // (its angle is a function of time). Everything else animates
            // on @Published triggers (hover, data refresh, alert engine).
            ZStack {
                GlowLayer(isExpanded: model.state == .expanded, hovering: hovering)
                    .overlay {
                        // Material background for the expanded panel content.
                        // Lives outside the silhouette so it can bleed past
                        // the silhouette on every side, no layout impact.
                        // Opacity tied to contentVisible so it fades alongside
                        // the panel content (220ms after hover-in, immediately
                        // on hover-out) and the .frame here tracks model.size,
                        // so the halo grows/shrinks with the spring morph.
                        IslandShape()
                            .fill(.ultraThinMaterial)
                            .padding(-9)
                            .blur(radius: 8)
                            .opacity(contentVisible ? 0.55 : 0)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .top) {
                        // Unified Provider Units with "space-around" distribution.
                        // Fixed edge padding (14) and growing Spacers (min 12) between
                        // every unit. SwiftUI automatically distributes them evenly.
                        HStack(spacing: 0) {
                            let visible = visibleProviders()
                            let count = visible.count
                            let leadingCount = count / 2
                            
                            Color.clear.frame(width: 14) // Fixed space before first element

                            ForEach(Array(visible.enumerated()), id: \.offset) { idx, p in
                                if idx > 0 {
                                    Spacer(minLength: 12) // Spacer that grows
                                }
                                
                                unit(for: p, alignment: idx < leadingCount ? .leading : .trailing)
                            }

                            Color.clear.frame(width: 14) // Fixed space after last element
                        }
                        .frame(width: model.size.width)
                        .frame(height: model.notch.height)
                    }
                    .overlay(alignment: .bottomLeading) {
                        // Utility control, not dashboard status. Keep it in a
                        // quiet corner so the footer remains about live data.
                        if model.state == .expanded {
                            SettingsButton()
                                .opacity(contentVisible ? 1 : 0)
                                .padding(6)
                        }
                    }
                    .contentShape(IslandShape())
                    .onTapGesture {
                        // Cmd-click cycles the visualization style of whichever
                        // page is active. Usage rotates Ring/Bar/Stepped/Numeric/
                        // Spark; cost rotates USD/VALUE/TOKENS/TREND.
                        if NSEvent.modifierFlags.contains(.command) {
                            switch ScreenPref.shared.screen {
                            case .usage: StylePref.shared.cycle()
                            case .cost:  CostStylePref.shared.cycle()
                            }
                            return
                        }
                        // Plain click: enter the full panel. Works from .peek
                        // (auto-crossing) or .compact (manual).
                        guard model.state != .expanded else { return }
                        withAnimation(.openMorph) {
                            model.setState(.expanded)
                            contentVisible = true
                            pillsVisible = false // Chrome fades out
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            hovering = true
                            guard model.state == .compact else { return }
                            withAnimation(.openMorph) {
                                model.setState(.peek)
                            }
                            // Text/dots fade in slightly behind the shape expand.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                guard hovering, model.state == .peek else { return }
                                withAnimation(.easeIn(duration: 0.18)) {
                                    pillsVisible = true
                                }
                            }
                        case .ended:
                            hovering = false
                            guard model.state != .compact else { return }
                            withAnimation(.closeMorph) {
                                model.setState(.compact)
                            }
                            withAnimation(.easeOut(duration: 0.08)) {
                                pillsVisible = false
                            }
                            withAnimation(.easeOut(duration: 0.10)) {
                                contentVisible = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                                guard !hovering else { return }
                                withAnimation(.closeMorph) {
                                    model.setState(.compact)
                                }
                            }
                        }
                    }
                
                // Expanded content area.
                if model.state == .expanded {
                    VStack(spacing: 0) {
                        PanelHeader(notch: model.notch)
                        PagedContent()
                        PanelFooter()
                    }
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : -8)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .allowsHitTesting(contentVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .onAppear {
                        // Re-sync scroll whenever we expand. CostStore/UsageStore
                        // might have polled in the background while the island
                        // was compact.
                        Task {
                            usageStore.refresh()
                            CostStore.shared.refresh()
                        }

                        // Auto-dismiss hint for first-time users.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                            guard !screenPref.hasSwipedScreen else { return }
                            // visual nudge: swipe the screen 10pt then back.
                        }
                    }
                }
            }
            .frame(width: model.size.width, height: model.size.height)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CodexIsland panel")
        .accessibilityHint(accessibilityHintForState)
        .onAppear {
            if claudeLogo == nil {
                claudeLogo = Bundle.main.url(forResource: "claude_logo", withExtension: "png")
                    .flatMap { NSImage(contentsOf: $0) }
            }
            if openaiLogo == nil {
                openaiLogo = Bundle.main.url(forResource: "openai_logo", withExtension: "png")
                    .flatMap { NSImage(contentsOf: $0) }
            }
            if geminiLogo == nil {
                geminiLogo = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Gemini")
            }
            model.visibleProviderCount = visibleProviders().count
        }
        .onChange(of: visibility.claudeVisible) { _ in model.visibleProviderCount = visibleProviders().count }
        .onChange(of: visibility.codexVisible) { _ in model.visibleProviderCount = visibleProviders().count }
        .onChange(of: visibility.geminiVisible) { _ in model.visibleProviderCount = visibleProviders().count }
        .onReceive(AlertEngine.shared.$pulseEvent) { event in
            guard let event, event.id != pulseToken else { return }
            pulseToken = event.id
            handlePulse(event)
            // Consume the event so a re-emission with the same id doesn't
            // re-trigger; the engine writes a fresh PulseEvent for each new
            // crossing tick.
            AlertEngine.shared.pulseEvent = nil
        }
    }

    /// Force-extends the island into peek state for ~4s when the alert
    /// engine signals a fresh threshold crossing. Suppressed when the panel
    /// is already expanded — the user is already looking at the data.
    private func handlePulse(_ event: AlertEngine.PulseEvent) {
        guard model.state != .expanded else { return }

        if model.state == .compact {
            withAnimation(.openMorph) {
                model.setState(.peek)
            }
            // Match the hover-in cadence so the pulse looks identical to a
            // user-initiated peek: shape commits first, content follows.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                guard model.state == .peek else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    pillsVisible = true
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            // If the user is hovering or has expanded the panel meanwhile,
            // don't fight their state — let their interaction own the peek
            // lifecycle from here.
            guard !hovering, model.state == .peek else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                pillsVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                guard !hovering, model.state == .peek else { return }
                withAnimation(.closeMorph) {
                    model.setState(.compact)
                }
            }
        }
    }

    private var accessibilityHintForState: String {
        switch model.state {
        case .compact:  return "Hover to peek usage. Click to expand. Command-click to cycle visualization."
        case .peek:     return "Click to expand. Command-click to cycle visualization."
        case .expanded: return "Command-click to cycle visualization."
        }
    }

    private struct ProviderUnits {
        var leading: [VisibleLogoProvider]
        var trailing: [VisibleLogoProvider]
    }

    private func balancedDistribution(for visible: [VisibleLogoProvider]) -> ProviderUnits {
        var units = ProviderUnits(leading: [], trailing: [])
        let count = visible.count
        
        // For N=3: 1 leading, 2 trailing. [Claude] | [Notch] | [Codex, Gemini]
        // This keeps Codex in the middle of the whole sequence.
        let trailingCount = count / 2
        let leadingCount = count - trailingCount
        
        for (idx, p) in visible.enumerated() {
            if idx < leadingCount {
                units.leading.append(p)
            } else {
                units.trailing.append(p)
            }
        }
        return units
    }

    @ViewBuilder
    private func unit(for p: VisibleLogoProvider, alignment: HorizontalAlignment) -> some View {
        let isVisible = ProviderVisibilityStore.shared.effectiveVisible(provider: p.provider)
        let isCompact = model.state == .compact
        
        NotchPeekPill(
            usage: currentUsage(for: p.provider),
            loading: usageStore.loading,
            tint: p.color,
            alignment: alignment,
            severity: currentSeverity(for: p.provider),
            icon: p.logo,
            isCompact: isCompact
        )
        .opacity(isVisible ? 1 : 0)
        .animation(.openMorph, value: isVisible)
        .offset(x: isCompact ? 0 : (pillsVisible ? 0 : (alignment == .leading ? -6 : 6)))
        .opacity(isCompact ? 1 : (pillsVisible ? 1 : 0))
    }

    private func currentUsage(for provider: AlertEngine.Provider) -> WindowUsage {
        switch provider {
        case .claude: return usageStore.claude.fiveHour
        case .codex:  return usageStore.codex.fiveHour
        case .gemini: return usageStore.gemini.fiveHour
        }
    }

    private func currentSeverity(for provider: AlertEngine.Provider) -> AlertEngine.Severity {
        switch provider {
        case .claude: return AlertEngine.shared.claudeSeverity
        case .codex:  return AlertEngine.shared.codexSeverity
        case .gemini: return AlertEngine.shared.geminiSeverity
        }
    }

    private struct VisibleLogoProvider {
        let provider: AlertEngine.Provider
        let logo: NSImage?
        let color: Color
    }

    private func visibleProviders() -> [VisibleLogoProvider] {
        var out: [VisibleLogoProvider] = []
        if ProviderVisibilityStore.shared.claudeVisible {
            out.append(VisibleLogoProvider(provider: .claude, logo: claudeLogo, color: IslandColor.claude))
        }
        if ProviderVisibilityStore.shared.codexVisible {
            out.append(VisibleLogoProvider(provider: .codex, logo: openaiLogo, color: IslandColor.codex))
        }
        if ProviderVisibilityStore.shared.geminiVisible {
            out.append(VisibleLogoProvider(provider: .gemini, logo: geminiLogo, color: IslandColor.gemini))
        }
        return out
    }

    /// Logo's distance from the silhouette's leading/trailing edge.
    private var logoEdgePadding: CGFloat {
        return 0
    }
}

/// Silhouette + halo + animated sweep. Bundles every layer whose
/// appearance depends on alert severity or the Low Power Mode event
/// predicate, so a UsageStore/AlertEngine/CostStore emission only
/// invalidates this child's body — not the root view's overlays,
/// gestures, or expanded-content branch.
private struct GlowLayer: View {
    let isExpanded: Bool
    let hovering: Bool

    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var costStore = CostStore.shared
    @ObservedObject private var lowPower = LowPowerModeStore.shared
    @ObservedObject private var alerts = AlertEngine.shared
    @ObservedObject private var occlusion = WindowOcclusionStore.shared

    var body: some View {
        ZStack {
            LoadingSweep(
                active: !occlusion.isOccluded
                    && (lowPower.effectiveEnabled ? glowEventActive : true),
                tint: glowColor
            )

            IslandShape()
                .fill(.black)
                .overlay {
                    IslandShape()
                        .strokeBorder(
                            .white.opacity(isExpanded ? 0.12 : 0),
                            lineWidth: 0.5
                        )
                }
                // Halo follows LPM's event predicate: under LPM it's
                // suppressed at rest and lights up only on refresh,
                // hover, or an active alert. Off-LPM it stays at the
                // ambient 0.35 the way it always has.
                .shadow(
                    color: glowColor.opacity(
                        lowPower.effectiveEnabled ? (glowEventActive ? 0.35 : 0) : 0.35
                    ),
                    radius: 14, y: 0
                )
                .animation(.easeInOut(duration: 0.25), value: glowEventActive)
                // 0.45s cross-fade so a threshold crossing (e.g. 79%→80%)
                // doesn't visibly snap the hue from cobalt to amber.
                .animation(.easeInOut(duration: 0.45), value: alerts.severity)
                .shadow(
                    color: isExpanded ? .black.opacity(0.5) : .clear,
                    radius: 20, y: 10
                )
        }
    }

    /// Under Low Power Mode the halo + sweep are gated on this predicate:
    /// the user sees glow only when something is happening (a fetch is in
    /// flight, the cursor is hovering, or an alert is active). Off-LPM it's
    /// ignored — both surfaces run continuously.
    private var glowEventActive: Bool {
        hovering
            || usageStore.loading
            || costStore.loading
            || alerts.severity != .none
    }

    /// Silhouette glow color. Cobalt is the ambient default; alert
    /// thresholds replace it with amber/red so the user gets the signal
    /// passively, even before hovering. All three share the same opacity
    /// so the glow's visual weight is constant — only the hue signals
    /// severity.
    private var glowColor: Color {
        switch alerts.severity {
        case .none:     return IslandColor.cobalt
        case .warning:  return IslandColor.alertAmber
        case .critical: return IslandColor.alertRed
        }
    }
}

/// Per-provider brand logo overlay.
/// NOTE: This is now mostly deprecated by NotchPeekPill pairing,
/// but kept for types/consistency until final cleanup.
private struct LogoOverlay: View {
    let image: NSImage?
    let color: Color
    let provider: AlertEngine.Provider
    let edgePadding: CGFloat
    let topPadding: CGFloat

    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .padding(provider == .claude ? .leading : .trailing, edgePadding)
                .padding(.top, topPadding)
                .opacity(isVisible ? 1 : 0)
                .animation(.openMorph, value: isVisible)
                .accessibilityLabel(isVisible ? providerLabel : "\(providerLabel) (hidden)")
                .accessibilityHidden(!isVisible)
        }
    }

    private var isVisible: Bool {
        visibility.effectiveVisible(provider: provider)
    }

    private var providerLabel: String {
        switch provider {
        case .claude: return "Claude"
        case .codex:  return "OpenAI"
        case .gemini: return "Gemini"
        }
    }
}

/// Percentage pill container — Logic moved into units loop.
private struct PeekPillOverlay: View {
    let provider: AlertEngine.Provider
    let topPadding: CGFloat
    let pillsVisible: Bool

    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var alerts = AlertEngine.shared

    var body: some View {
        EmptyView() // Moved into responsive units loop
    }
}

/// Cobalt angular-gradient sweep that orbits the silhouette while data is
/// fetching. Owns its own TimelineView so the parent (IslandRootView) doesn't
/// re-render every overlay alongside the sweep — that was competing with the
/// hover spring for main-thread budget.
private struct LoadingSweep: View {
    let active: Bool
    /// Color of the orbiting trail. Cobalt by default; switches to amber
    /// or red while the alert engine reports a tracked window above its
    /// warning/critical threshold so the entire glow shares one hue.
    let tint: Color

    var body: some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let rotation = (t * 100).truncatingRemainder(dividingBy: 360)
                IslandShape()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: tint.opacity(0.0), location: 0.55),
                                .init(color: tint, location: 0.78),
                                .init(color: .white.opacity(0.95), location: 0.92),
                                .init(color: tint.opacity(0.0), location: 1.00),
                            ]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        lineWidth: 4
                    )
                    .blur(radius: 3)
            }
        }
    }
}
