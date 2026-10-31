import Foundation

/// Page-change decision for scroll-wheel ticks: Shift+wheel on any device,
/// or a plain horizontal wheel such as a mouse thumb wheel. Ticks carry no
/// gesture phases and one flick sends several, so after a change further
/// ticks are ignored for a short window.
enum WheelSwipe {
    enum Direction { case advance, rewind }

    static let debounce: TimeInterval = 0.4

    static func direction(deltaX: CGFloat, deltaY: CGFloat, shift: Bool,
                          now: TimeInterval, lastChange: TimeInterval) -> Direction? {
        let delta: CGFloat
        if shift {
            // macOS may or may not swap the axes with Shift held, so read
            // whichever one carries signal.
            delta = abs(deltaX) > abs(deltaY) ? deltaX : deltaY
        } else {
            guard abs(deltaX) > abs(deltaY) else { return nil }
            delta = deltaX
        }
        guard abs(delta) > 0.5, now - lastChange >= debounce else { return nil }
        // Natural-scrolling convention: negative delta moves to the next page.
        return delta < 0 ? .advance : .rewind
    }
}
