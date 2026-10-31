import Foundation

/// Page-change decision for scroll-wheel ticks: Shift+wheel on any device,
/// or a plain horizontal wheel such as a mouse thumb wheel. Ticks carry no
/// gesture phases and one flick sends a burst of them, so a burst counts as
/// one gesture: only its first tick after an idle gap changes the page.
enum WheelSwipe {
    enum Direction { case advance, rewind }

    static let idleGap: TimeInterval = 0.4

    /// The delta on the paging axis, or nil when the tick is not a page gesture.
    static func pageDelta(deltaX: CGFloat, deltaY: CGFloat, shift: Bool) -> CGFloat? {
        let delta: CGFloat
        if shift {
            // macOS may or may not swap the axes with Shift held, so read
            // whichever one carries signal.
            delta = abs(deltaX) > abs(deltaY) ? deltaX : deltaY
        } else {
            guard abs(deltaX) > abs(deltaY) else { return nil }
            delta = deltaX
        }
        return abs(delta) > 0.5 ? delta : nil
    }

    /// `lastTick` is the previous qualifying tick, fired or not; callers must
    /// record every qualifying tick so a long burst stays one gesture.
    static func direction(delta: CGFloat, now: TimeInterval, lastTick: TimeInterval) -> Direction? {
        guard now - lastTick >= idleGap else { return nil }
        // Natural-scrolling convention: negative delta moves to the next page.
        return delta < 0 ? .advance : .rewind
    }
}
