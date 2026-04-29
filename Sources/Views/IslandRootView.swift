import SwiftUI
import AppKit

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
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
                .overlay(alignment: .topLeading) {
                    logo(claudeLogo, color: IslandColor.claude, alignment: .leading)
                }
                .overlay(alignment: .topTrailing) {
                    logo(openaiLogo, color: IslandColor.codex, alignment: .trailing)
                }
                .contentShape(IslandShape())
                .onTapGesture {
                    // Cmd-click cycles the chart style. The chart crossfade
                    // (.id(style) on ChartTile) is the confirmation; no
                    // panel-wide press scale needed — at this size, scaling
                    // the whole 720pt panel reads as way too much for what's
                    // really a 1-character UI change.
                    if NSEvent.modifierFlags.contains(.command) {
                        StylePref.shared.cycle()
                    }
                }
                .onHover { h in
                    hovering = h
                    if h {
                        // Subtle trackpad tap on hover-in. .alignment is
                        // macOS's lightest pattern (designed for snap-to-grid
                        // feedback) so it reads as a confirmation, not a
                        // notification. No-op if the user has haptics off
                        // in System Settings.
                        NSHapticFeedbackManager.defaultPerformer.perform(
                            .alignment, performanceTime: .now
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
