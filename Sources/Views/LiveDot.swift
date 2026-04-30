import SwiftUI

/// Breathing live-status dot. Active = teal with a pulsing outer halo;
/// inactive = dim white. Driven by TimelineView so the breath ticks at
/// display refresh rate. Briefly bumps on each fresh sync so the user can
/// see new data has just landed.
struct LiveDot: View {
    let active: Bool
    @ObservedObject private var store = UsageStore.shared
    @State private var syncBump: CGFloat = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            // sin(phase * 2.6) ≈ 2.4s breath cycle. Slow enough to feel
            // like a heartbeat at rest, not a strobe.
            let pulse = 0.6 + 0.4 * (sin(phase * 2.6) * 0.5 + 0.5)
            ZStack {
                Circle()
                    .fill(active ? IslandColor.liveTeal.opacity(0.9) : Color.white.opacity(0.25))
                Circle()
                    .stroke(active ? IslandColor.liveTeal : .clear, lineWidth: 1)
                    .scaleEffect(active ? CGFloat(1 + pulse * 0.6) : 1)
                    .opacity(active ? 0.55 * (1 - pulse) : 0)
            }
            .frame(width: 6, height: 6)
            .shadow(color: active ? IslandColor.liveTeal.opacity(0.55) : .clear, radius: 3)
        }
        .scaleEffect(syncBump)
        // Two-phase bump on each fresh sync: snap up to 1.18, then settle
        // back to 1.0 over strongEaseOut. Reads as "data just arrived" —
        // the breath continues underneath, the bump rides on top.
        .onChange(of: store.lastUpdated) { _ in
            withAnimation(.strongEaseOut) { syncBump = 1.18 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.strongEaseOut) { syncBump = 1.0 }
            }
        }
        .accessibilityHidden(true)
    }
}
