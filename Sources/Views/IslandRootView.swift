import SwiftUI
import AppKit

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var visibility = ProviderVisibilityStore.shared
    @ObservedObject private var usageStore = UsageStore.shared
    @ObservedObject private var costStore = CostStore.shared
    @State private var hovering = false
    @State private var contentVisible = false

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
                    // Spark; cost rotates USD/VALUE/TOKENS/TREND. The cell
                    // crossfade is the confirmation — no panel-wide press
                    // scale needed.
                    if NSEvent.modifierFlags.contains(.command) {
                        switch ScreenPref.shared.screen {
                        case .usage: StylePref.shared.cycle()
                        case .cost:  CostStylePref.shared.cycle()
                        }
                    }
                }
                .onHover { h in
                    hovering = h
                    if h {
                        // Trackpad tap on hover-in. .levelChange is one step
                        // up from .alignment — closer to a volume-key tick,
                        // still well short of the .generic notification
                        // pattern. No-op if the user has haptics off in
                        // System Settings.
                        NSHapticFeedbackManager.defaultPerformer.perform(
                            .levelChange, performanceTime: .now
                        )
                        // ENTER: shape morphs first (logos slide outward with
                        // it). Once the shape is mostly grown (~220ms), fade
                        // in the expanded content with a small slide-down.
                        withAnimation(.openMorph) {
                            model.setState(.expanded)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            guard model.state == .expanded else { return }
                            withAnimation(.strongEaseOut) {
                                contentVisible = true
                            }
                        }
                    } else {
                        // EXIT: content fades out first (100ms easeOut), then
                        // the shape shrinks. This way the shape never visibly
                        // reflows around content mid-collapse.
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
        .accessibilityHint(model.state == .compact
            ? "Hover to expand. Command-click to cycle visualization."
            : "Command-click to cycle visualization.")
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
                .padding(alignment == .leading ? .leading : .trailing, 9)
                .padding(.top, max(0, (model.notch.height - 20) / 2))
        }
    }
}
