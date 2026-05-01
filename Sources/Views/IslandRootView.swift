import SwiftUI
import AppKit

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var costStore = CostStore.shared
    @State private var hovering = false
    @State private var contentVisible = false
    @State private var pillsVisible = false

    static let tabWidth: CGFloat = 38

    private var claudeLogo: NSImage? {
        Bundle.main.url(forResource: "claude_logo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }

    private var openaiLogo: NSImage? {
        Bundle.main.url(forResource: "openai_logo", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // minimumInterval: 1/120 explicitly opts the timeline into the
            // ProMotion refresh rate. Default `.animation` schedules can
            // settle at 60Hz even on 120Hz displays, especially in
            // .accessory background apps.
            TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let rotation = (t * 100).truncatingRemainder(dividingBy: 360)

                ZStack {
                    // Loading sweep. 3pt blur + 4pt stroke is half the GPU
                    // cost of the original 5/5 — at 120Hz the blur is hot
                    // because the angular gradient re-rasterizes per frame.
                    if usageStore.loading || costStore.loading {
                        IslandShape()
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .clear, location: 0.00),
                                        .init(color: IslandColor.cobalt.opacity(0.0), location: 0.55),
                                        .init(color: IslandColor.cobalt, location: 0.78),
                                        .init(color: .white.opacity(0.95), location: 0.92),
                                        .init(color: IslandColor.cobalt.opacity(0.0), location: 1.00),
                                    ]),
                                    center: .center,
                                    angle: .degrees(rotation)
                                ),
                                lineWidth: 4
                            )
                            .blur(radius: 3)
                    }

                    IslandShape()
                        .fill(.black)
                        .overlay {
                            IslandShape()
                                .strokeBorder(
                                    .white.opacity(model.state == .expanded ? 0.12 : 0),
                                    lineWidth: 0.5
                                )
                        }
                        .shadow(color: IslandColor.cobalt.opacity(0.35), radius: 14, y: 0)
                        .shadow(
                            color: model.state == .expanded ? .black.opacity(0.5) : .clear,
                            radius: 20, y: 10
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
                    logo(claudeLogo, color: IslandColor.claude, alignment: .leading)
                        .opacity(visibility.claudeVisible ? 1 : 0.30)
                        .saturation(visibility.claudeVisible ? 1 : 0)
                        .accessibilityLabel(visibility.claudeVisible ? "Claude" : "Claude (hidden)")
                }
                .overlay(alignment: .topTrailing) {
                    logo(openaiLogo, color: IslandColor.codex, alignment: .trailing)
                        .opacity(visibility.codexVisible ? 1 : 0.30)
                        .saturation(visibility.codexVisible ? 1 : 0)
                        .accessibilityLabel(visibility.codexVisible ? "OpenAI" : "OpenAI (hidden)")
                }
                .overlay(alignment: .topLeading) {
                    // Pill lives in the new outboard slot (the 78pt the
                    // silhouette grew on entering peek). 14pt inset from the
                    // silhouette's new leading edge keeps it visually
                    // breathing inside the rounded corner.
                    if model.state != .compact && visibility.claudeVisible {
                        NotchPeekPill(
                            usage: usageStore.claude.fiveHour,
                            loading: usageStore.loading,
                            tint: IslandColor.claude,
                            alignment: .leading
                        )
                        .padding(.leading, 14)
                        .padding(.top, max(0, (model.notch.height - 14) / 2))
                        .opacity(pillsVisible ? 1 : 0)
                        .offset(x: pillsVisible ? 0 : -6)
                        .allowsHitTesting(false)
                        .accessibilityLabel(peekLabel(for: usageStore.claude.fiveHour, provider: "Claude"))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if model.state != .compact && visibility.codexVisible {
                        NotchPeekPill(
                            usage: usageStore.codex.fiveHour,
                            loading: usageStore.loading,
                            tint: IslandColor.codex,
                            alignment: .trailing
                        )
                        .padding(.trailing, 14)
                        .padding(.top, max(0, (model.notch.height - 14) / 2))
                        .opacity(pillsVisible ? 1 : 0)
                        .offset(x: pillsVisible ? 0 : 6)
                        .allowsHitTesting(false)
                        .accessibilityLabel(peekLabel(for: usageStore.codex.fiveHour, provider: "Codex"))
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
                    // Spark; cost rotates USD/VALUE/TOKENS/TREND.
                    if NSEvent.modifierFlags.contains(.command) {
                        switch ScreenPref.shared.screen {
                        case .usage: StylePref.shared.cycle()
                        case .cost:  CostStylePref.shared.cycle()
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
                        // EXIT: pills fade first, then shape collapses.
                        // Branches by state so peek-out shrinks to compact
                        // and expanded-out collapses the panel content too.
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
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CodexIsland panel")
        .accessibilityHint(accessibilityHintForState)
    }

    private var accessibilityHintForState: String {
        switch model.state {
        case .compact:  return "Hover to peek usage. Click to expand. Command-click to cycle visualization."
        case .peek:     return "Click to expand. Command-click to cycle visualization."
        case .expanded: return "Command-click to cycle visualization."
        }
    }

    private func peekLabel(for window: WindowUsage, provider: String) -> String {
        if window.error != nil && window.usedPercent == 0 {
            return "\(provider): no data for 5-hour window"
        }
        let pct = Int((window.usedPercent * 100).rounded())
        guard let resetAt = window.resetAt else {
            return "\(provider): \(pct) percent of 5-hour window used"
        }
        let remaining = max(0, resetAt.timeIntervalSinceNow)
        let resetPhrase: String = remaining >= 3600
            ? "resets in \(Int((remaining / 3600).rounded(.down))) hours"
            : "resets in \(max(1, Int((remaining / 60).rounded(.down)))) minutes"
        return "\(provider): \(pct) percent of 5-hour window used, \(resetPhrase)"
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

    @ViewBuilder
    private func logo(_ image: NSImage?, color: Color, alignment: HorizontalAlignment) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .padding(alignment == .leading ? .leading : .trailing, logoEdgePadding)
                .padding(.top, max(0, (model.notch.height - 20) / 2))
        }
    }
}
