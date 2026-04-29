import SwiftUI
import AppKit

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    /// Visible side extensions housing the brand logos in compact state.
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
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let rotation = (t * 100).truncatingRemainder(dividingBy: 360)

                ZStack {
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
                            lineWidth: 5
                        )
                        .blur(radius: 5)

                    IslandShape()
                        .fill(.black)
                        .shadow(color: IslandColor.cobalt.opacity(0.35), radius: 14, y: 0)
                }
                .frame(width: model.size.width, height: model.size.height)
                // Logos always visible — anchored to the morphing shape edges.
                // Don't fade them in/out; they slide WITH the shape on
                // expand/collapse so they appear to flow smoothly.
                .overlay(alignment: .topLeading) {
                    logo(claudeLogo, color: IslandColor.claude, alignment: .leading)
                }
                .overlay(alignment: .topTrailing) {
                    logo(openaiLogo, color: IslandColor.codex, alignment: .trailing)
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
