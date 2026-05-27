import SwiftUI
import AppKit

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var alwaysShow = AlwaysShowUsageStore.shared
    @State private var hovering = false
    @State private var contentVisible = false
    @State private var pillsVisible = false
    @State private var pulseToken: UUID?

    /// Image decode from disk is ~150µs per call. Computed properties
    /// re-decoded both logos every render — inside a 120Hz TimelineView
    /// that's 240 main-thread decodes/sec. Cache once on appear.
    @State private var claudeLogo: NSImage?
    @State private var openaiLogo: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            // Only the rotating loading sweep needs per-frame re-renders
            // (its angle is a function of time). Everything else animates
            // via withAnimation springs paced by display sync, so wrapping
            // the whole tree in TimelineView would re-build every overlay
            // and every gesture closure 120 times per second — competing
            // with the spring for main-thread budget and showing up as
            // hover-spring jank.
            ZStack {
                GlowLayer(
                    isExpanded: model.state == .expanded,
                    hovering: hovering
                )

                if model.state == .expanded {
                    ExpandedView(model: model)
                        .opacity(contentVisible ? 1 : 0)
                        // Slide down from -8 → 0 on enter pairs with the
                        // 100ms→180ms opacity delay set in onHover. On
                        // exit the offset never matters because the
                        // content fully fades before the shape shrinks.
                        .offset(y: contentVisible ? 0 : -8)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .allowsHitTesting(contentVisible)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: model.size.width, height: model.size.height)
            .background {
                    // Frosted halo. ultraThinMaterial is a backdrop blur of
                    // whatever desktop content is behind the window. Lives
                    // in .background AFTER .frame so it doesn't push the
                    // ZStack's layout box larger than model.size — earlier
                    // attempts that put the halo as a sibling inside the
                    // ZStack with its own oversized .frame ended up
                    // expanding the parent bounds, throwing the logo
                    // overlays off and breaking the compact pill alignment
                    // with the physical notch.
                    //
                    // .padding(-9) extends only the rendering by 9pt past
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
                .overlay(alignment: .topLeading) {
                    LogoOverlay(
                        image: claudeLogo,
                        color: IslandColor.claude,
                        provider: .claude,
                        edgePadding: logoEdgePadding,
                        topPadding: max(0, (model.notch.height - 20) / 2)
                    )
                }
                .overlay(alignment: .topTrailing) {
                    LogoOverlay(
                        image: openaiLogo,
                        color: IslandColor.codex,
                        provider: .codex,
                        edgePadding: logoEdgePadding,
                        topPadding: max(0, (model.notch.height - 20) / 2)
                    )
                }
                .overlay(alignment: .topLeading) {
                    // Pill lives in the new outboard slot (the 78pt the
                    // silhouette grew on entering peek). 14pt inset from the
                    // silhouette's new leading edge keeps it visually
                    // breathing inside the rounded corner.
                    if model.state != .compact {
                        PeekPillOverlay(
                            provider: .claude,
                            topPadding: max(0, (model.notch.height - 14) / 2),
                            pillsVisible: pillsVisible
                        )
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if model.state != .compact {
                        PeekPillOverlay(
                            provider: .codex,
                            topPadding: max(0, (model.notch.height - 14) / 2),
                            pillsVisible: pillsVisible
                        )
                    }
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
                    // Spark; cost rotates USD/VALUE/TOKENS/TREND. Overview
                    // is fixed to year-to-date.
                    if NSEvent.modifierFlags.contains(.command) {
                        switch ScreenPref.shared.screen {
                        case .usage: StylePref.shared.cycle()
                        case .cost:  CostStylePref.shared.cycle()
                        case .overview: return
                        }
                        return
                    }
                    // Plain click: enter the full panel. Works from .peek
                    // (the common case after hover) or .compact (cold click).
                    // Pills travel outward with the growing shape under the
                    // single openMorph spring, then quietly retire after the
                    // expanded content has settled.
                    guard model.state == .peek || model.state == .compact else { return }
                    withAnimation(.openMorph) {
                        model.setState(.expanded)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        guard model.state == .expanded else { return }
                        withAnimation(.strongEaseOut) {
                            contentVisible = true
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeIn(duration: 0.18)) {
                            pillsVisible = false
                        }
                    }
                }
                .onHover { h in
                    hovering = h
                    if h {
                        // Trackpad tap on hover-in. .levelChange is closer to
                        // a volume-key tick than the .generic notification
                        // pattern. No-op if haptics are off.
                        NSHapticFeedbackManager.defaultPerformer.perform(
                            .levelChange, performanceTime: .now
                        )
                        // PEEK ENTER: shape morphs out to peek width. Pills
                        // fade in 60ms later so the eye sees the shape commit
                        // first, then content arrives. Hover does NOT open
                        // the full panel — that requires a click.
                        if model.state == .compact {
                            withAnimation(.openMorph) {
                                model.setState(.peek)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                                guard model.state == .peek else { return }
                                withAnimation(.easeOut(duration: 0.18)) {
                                    pillsVisible = true
                                }
                            }
                        }
                    } else {
                        // EXIT: pills fade first (unless we're pinning peek),
                        // then the shape settles at the rest state — `.compact`
                        // normally, `.peek` under always-show.
                        if !alwaysShow.enabled {
                            withAnimation(.easeOut(duration: 0.08)) {
                                pillsVisible = false
                            }
                        }
                        withAnimation(.easeOut(duration: 0.10)) {
                            contentVisible = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                            guard !hovering else { return }
                            // Re-read restState here — the user may have flipped
                            // the always-show toggle during the 100ms wait, and
                            // a captured-at-creation-time `target` would settle
                            // at the wrong state for them.
                            let target = restState
                            if model.state != target {
                                withAnimation(.closeMorph) {
                                    model.setState(target)
                                }
                            }
                            // Coming out of `.expanded` under always-show, the
                            // pills were hidden by the open-panel branch — bring
                            // them back as the shape resettles at peek.
                            if alwaysShow.enabled && !pillsVisible {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    pillsVisible = true
                                }
                            }
                        }
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("CodexIsland panel"))
        .accessibilityHint(accessibilityHintForState)
        .onAppear {
            if claudeLogo == nil {
                claudeLogo = Bundle.main.url(forResource: "claude_logo", withExtension: "pdf")
                    .flatMap { NSImage(contentsOf: $0) }
            }
            if openaiLogo == nil {
                openaiLogo = Bundle.main.url(forResource: "openai_logo", withExtension: "pdf")
                    .flatMap { NSImage(contentsOf: $0) }
            }
            // Snap to peek on launch when the user has opted into always-show.
            // No animation here — the window is just becoming visible, so the
            // user sees the silhouette appear already at peek width rather
            // than morphing out under their gaze.
            if alwaysShow.enabled && model.state == .compact {
                model.setState(.peek)
                pillsVisible = true
            }
        }
        .onChange(of: alwaysShow.enabled) { enabled in
            // Live toggle — defer to the user's current interaction. If they
            // happen to be hovering, the hover state machine owns the morph
            // and will land on the new rest state on hover-out. If the panel
            // is expanded, leave it alone for the same reason.
            guard !hovering, model.state != .expanded else { return }
            if enabled {
                if model.state == .compact {
                    withAnimation(.openMorph) {
                        model.setState(.peek)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                        guard model.state == .peek, !hovering else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            pillsVisible = true
                        }
                    }
                }
            } else {
                if model.state == .peek {
                    withAnimation(.easeOut(duration: 0.08)) {
                        pillsVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                        // Re-check `alwaysShow.enabled` — if the user toggled
                        // back on inside the 100ms wait, leave the peek state
                        // alone instead of fighting their newer intent.
                        guard !hovering, model.state == .peek, !alwaysShow.enabled else { return }
                        withAnimation(.closeMorph) {
                            model.setState(.compact)
                        }
                    }
                }
            }
        }
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
            // lifecycle from here. Under always-show, `.peek` IS the rest
            // state, so the pulse just resolves into the steady-state pill
            // rather than collapsing back to compact.
            guard !hovering, model.state == .peek, !alwaysShow.enabled else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                pillsVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                // Mirror the outer 4-second guard — if always-show flipped on
                // during the tiny inner wait, leave the peek state alone.
                guard !hovering, model.state == .peek, !alwaysShow.enabled else { return }
                withAnimation(.closeMorph) {
                    model.setState(.compact)
                }
            }
        }
    }

    private var restState: IslandModel.State {
        alwaysShow.enabled ? .peek : .compact
    }

    private var accessibilityHintForState: String {
        switch model.state {
        case .compact:
            return alwaysShow.enabled
                ? L10n.tr("Click to expand. Command-click to cycle visualization.")
                : L10n.tr("Hover to peek usage. Click to expand. Command-click to cycle visualization.")
        case .peek:     return L10n.tr("Click to expand. Command-click to cycle visualization.")
        case .expanded:
            return ScreenPref.shared.screen == .overview
                ? L10n.tr("Swipe to change pages.")
                : L10n.tr("Command-click to cycle visualization.")
        }
    }

    /// Logo's distance from the silhouette's leading/trailing edge. In
    /// `.peek` we offset the logo inward by `pillSlotWidth` so it stays
    /// physically pinned to its compact position while the silhouette grows
    /// outward — leaving the new outboard space for the percentage pill.
    /// Compact and expanded keep the logo at the silhouette edge (existing
    /// behavior; expanded panel layout depends on it).
    private var logoEdgePadding: CGFloat {
        switch model.state {
        case .compact, .expanded: return 9
        case .peek:               return model.pillSlotWidth + 9
        }
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

/// Per-provider brand logo overlay. Observes only ProviderVisibilityStore
/// so a UsageStore/CostStore tick doesn't re-render the logo image or
/// re-evaluate its accessibility label.
private struct LogoOverlay: View {
    let image: NSImage?
    let color: Color
    let provider: AlertEngine.Provider
    let edgePadding: CGFloat
    let topPadding: CGFloat

    @ObservedObject private var visibility = ProviderVisibilityStore.shared

    var body: some View {
        // Hidden providers fully drop out — header / peek pill / chrome
        // are gated identically. `.opacity(isVisible ? 1 : 0)` keeps the
        // view in the layout (so other overlays don't reflow) but makes
        // it invisible, and the explicit `.animation(.openMorph, value:)`
        // pairs the chrome fade with the panel layout swap when the user
        // toggles a provider in Settings.
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
                .accessibilityLabel(isVisible ? providerLabel : L10n.tr("%@ (hidden)", providerLabel))
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
        }
    }
}

/// Per-provider peek pill overlay. Observes ProviderVisibilityStore,
/// UsageStore, and AlertEngine — but not CostStore, so a Codex log
/// scan completing doesn't re-render the pill that has no cost data
/// in it.
private struct PeekPillOverlay: View {
    let provider: AlertEngine.Provider
    let topPadding: CGFloat
    let pillsVisible: Bool

    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var alerts = AlertEngine.shared

    var body: some View {
        let window = currentWindow
        NotchPeekPill(
            usage: window,
            loading: usageStore.loading,
            tint: tint,
            alignment: provider == .claude ? .leading : .trailing,
            severity: severity
        )
        .padding(provider == .claude ? .leading : .trailing, 14)
        .padding(.top, topPadding)
        // Two opacity bindings stack:
        //   - `pillsVisible` is the peek lifecycle (hover-in / hover-out).
        //   - `isVisible` is the user's settings toggle.
        // Both must be 1 to render. Animating `isVisible` with the same
        // openMorph spring as the panel layout keeps the toggle fade in
        // lockstep with the rest of the chrome.
        .opacity((pillsVisible && isVisible) ? 1 : 0)
        .animation(.openMorph, value: isVisible)
        .offset(x: pillsVisible ? 0 : (provider == .claude ? -6 : 6))
        .allowsHitTesting(false)
        .accessibilityLabel(peekLabel(for: window, provider: providerLabel))
        // Mirror the visual opacity gate exactly — both `pillsVisible` and
        // `isVisible` must be true for the pill to render. Keying the
        // accessibility hide on only `isVisible` lets VoiceOver reach a
        // pill that is visually invisible during the peek-out lifecycle.
        .accessibilityHidden(!(pillsVisible && isVisible))
    }

    private var isVisible: Bool {
        visibility.effectiveVisible(provider: provider)
    }

    private var currentWindow: WindowUsage {
        switch provider {
        case .claude: return usageStore.claude.fiveHour
        case .codex:  return usageStore.codex.fiveHour
        }
    }

    private var severity: AlertEngine.Severity {
        switch provider {
        case .claude: return alerts.claudeSeverity
        case .codex:  return alerts.codexSeverity
        }
    }

    private var tint: Color {
        switch provider {
        case .claude: return IslandColor.claude
        case .codex:  return IslandColor.codex
        }
    }

    private var providerLabel: String {
        switch provider {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }

    private func peekLabel(for window: WindowUsage, provider: String) -> String {
        if window.error != nil && window.usedPercent == 0 {
            return L10n.tr("%@: no data for 5-hour window", provider)
        }
        let pct = window.percentInt
        guard let resetAt = window.resetAt else {
            return L10n.tr("%@: %d percent of 5-hour window used", provider, pct)
        }
        let remaining = max(0, resetAt.timeIntervalSinceNow)
        let resetPhrase: String = remaining >= 3600
            ? L10n.tr("resets in %d hours", Int((remaining / 3600).rounded(.down)))
            : L10n.tr("resets in %d minutes", max(1, Int((remaining / 60).rounded(.down))))
        return L10n.tr("%@: %d percent of 5-hour window used, %@", provider, pct, resetPhrase)
    }
}

/// Cobalt angular-gradient sweep that orbits the silhouette while data is
/// fetching. Owns its own TimelineView so the parent (IslandRootView) doesn't
/// re-render every overlay alongside the sweep — that was competing with the
/// hover spring for main-thread budget.
///
/// Tick rate is 30Hz (was 120Hz). 3.6s/revolution at 30Hz = 12° per frame,
/// indistinguishable from 120Hz to the eye for a slow continuous orbit but
/// 4× cheaper on the main thread. The bigger CPU saving comes from gating
/// `active` on `!isWindowOccluded` upstream — when a fullscreen app or
/// another window covers the menu bar entirely, the sweep stops rendering
/// (the user can't see it anyway), dropping idle CPU to ~0%.
///
/// Earlier attempts to push rotation into Core Animation (CAGradientLayer or
/// `.rotationEffect` over a static gradient) all subtly changed the glow
/// feel — SwiftUI's per-frame conic re-shading produces an alive,
/// atmospheric look that a rotated static texture loses. This is the
/// minimum-cost approach that preserves the exact original render.
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
