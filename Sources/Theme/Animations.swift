import SwiftUI

extension Animation {
    /// Emil Kowalski's strong ease-out: cubic-bezier(0.23, 1, 0.32, 1).
    /// Punchier than the built-in .easeOut — more visible "settle" at the
    /// end. Use for non-spring UI transitions under 300ms.
    static let strongEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)

    /// Asymmetric springs on shape morph. Opening is leisurely (the user is
    /// reaching toward the panel and tracks the morph); closing is snappy
    /// (the system responds to the user moving away).
    static let openMorph = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let closeMorph = Animation.spring(response: 0.30, dampingFraction: 0.88)
}
