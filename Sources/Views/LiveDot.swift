import SwiftUI

/// Breathing live-status dot. Active = teal with a pulsing outer halo;
/// inactive = dim white. TimelineView ticks at 30Hz — imperceptible from
/// display rate for a 2.4s breath but 4× cheaper (same rationale as
/// LoadingSweep). Briefly bumps on each fresh sync so the user can
/// see new data has just landed.
struct LiveDot: View {
    let active: Bool
    @ObservedObject private var store = UsageStore.shared
    @State private var syncBump: CGFloat = 1.0

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                    // sin(phase * 2.6) ≈ 2.4s breath cycle. Slow enough to
                    // feel like a heartbeat at rest, not a strobe.
                    let pulse = 0.6 + 0.4 * (sin(phase * 2.6) * 0.5 + 0.5)
                    ZStack {
                        Circle()
                            .fill(IslandColor.liveTeal.opacity(0.9))
                        Circle()
                            .stroke(IslandColor.liveTeal, lineWidth: 1)
                            .scaleEffect(CGFloat(1 + pulse * 0.6))
                            .opacity(0.55 * (1 - pulse))
                    }
                    .frame(width: 6, height: 6)
                    .shadow(color: IslandColor.liveTeal.opacity(0.55), radius: 3)
                }
            } else {
                // Static dim circle when inactive — no TimelineView, no
                // breath cycle, no halo. Cheap.
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
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
