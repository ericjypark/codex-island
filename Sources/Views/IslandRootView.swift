import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    /// Visible side extensions housing the brand logos in compact state.
    static let tabWidth: CGFloat = 38

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                // 100°/sec ≈ 3.6s per revolution. Slower than the natural
                // ~140°/sec instinct because this is a near-permanent UI
                // element — visual noise compounds quickly.
                let rotation = (t * 100).truncatingRemainder(dividingBy: 360)

                ZStack {
                    // Cobalt comet-tail rotates around the perimeter. The
                    // brighter tip at 0.92 of the gradient gives it a
                    // recognizable head; everything before 0.55 is clear so
                    // the trail fades cleanly.
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

                    // Solid black fill on top of the sweep, so only the part
                    // of the sweep that bleeds outside the shape (the glow
                    // halo) is visible. Inside the physical notch this glow
                    // is also invisible, so the user sees the sweep as a
                    // moving cobalt halo around the bottom curve.
                    IslandShape()
                        .fill(.black)
                        .shadow(color: IslandColor.cobalt.opacity(0.35), radius: 14, y: 0)
                }
                .frame(width: model.size.width, height: model.size.height)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
