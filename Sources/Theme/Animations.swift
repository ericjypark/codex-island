import SwiftUI

extension Animation {
    /// Emil Kowalski's strong ease-out: cubic-bezier(0.23, 1, 0.32, 1).
    /// Punchier than the built-in .easeOut — more visible "settle" at the
    /// end. Use for non-spring UI transitions under 300ms.
    static let strongEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)

    /// Same curve, slightly faster — for content swaps where the cohesion
    /// reads better at 220ms (chart style change, etc).
    static let chartSwap = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)

    /// Shared hover / selection chrome crossfade. One duration for every
    /// "faint white wash" state change so the chrome reads as one product.
    static let hoverFade = Animation.easeOut(duration: 0.12)

    /// Horizontal page movement. Tuned between the too-snappy drawer curve
    /// and the slower full ease-in-out pass: responsive start, quiet settle.
    static let pageSwipe = Animation.timingCurve(0.25, 0.82, 0.25, 1, duration: 0.36)

    /// Asymmetric springs on shape morph. Opening is leisurely (the user is
    /// reaching toward the panel and tracks the morph); closing is snappy
    /// (the system responds to the user moving away).
    static let openMorph = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let closeMorph = Animation.spring(response: 0.30, dampingFraction: 0.88)

    /// Selected-day detail is a small disclosure inside an already-open
    /// panel, so it should be faster and more damped than the full island
    /// open. The collapse is shorter because exits should get out of the
    /// way before navigation continues.
    static let detailExpand = Animation.spring(response: 0.36, dampingFraction: 0.94)
    static let detailCollapse = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.20)
}

private struct BlurTransitionModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

/// Subtle scale-down on press so any pressable surface gives instant
/// feedback. Per Emil's rule: "buttons must feel responsive to press."
/// Scale stays in the 0.92–0.97 range; below that the press feels
/// rubbery, above it reads as no feedback at all. Animation is short
/// (110ms) so it tracks the user's finger.
struct PressableButtonStyle: ButtonStyle {
    let scale: CGFloat
    init(scale: CGFloat = 0.94) { self.scale = scale }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

extension AnyTransition {
    /// Blur + scale + opacity. Two crossfading shapes (Ring → Bar) read as
    /// one continuous transformation rather than two distinct objects
    /// stacked mid-fade. Per Emil's "blur masks imperfect transitions"
    /// rule — the eye perceives a single morph.
    static var chartSwap: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(radius: 3),
            identity: BlurTransitionModifier(radius: 0)
        )
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.96))
    }

    /// Small disclosure rows should not slide far enough to fight the panel
    /// resize. A tiny anchored scale + blur reads as material settling into
    /// place without shifting the surrounding grid.
    static var detailReveal: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(radius: 2),
            identity: BlurTransitionModifier(radius: 0)
        )
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.98, anchor: .top))
    }
}
