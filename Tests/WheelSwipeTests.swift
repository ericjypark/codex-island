import Foundation

@main
struct WheelSwipeTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func delta(_ dx: CGFloat, _ dy: CGFloat, shift: Bool = false) -> CGFloat? {
            WheelSwipe.pageDelta(deltaX: dx, deltaY: dy, shift: shift)
        }
        check(delta(-3, 0) == -3, "Horizontal-dominant tick is a page gesture")
        check(delta(-1, 0.4) == -1, "Slight vertical noise does not block a horizontal tick")
        check(delta(0, -3) == nil, "Vertical tick without Shift is not a page gesture")
        check(delta(-0.3, 0) == nil, "Sub-threshold horizontal delta is ignored")
        check(delta(0, -3, shift: true) == -3, "Shift+vertical wheel pages on the vertical delta")
        check(delta(-3, 0, shift: true) == -3, "Shift with swapped axis still reads horizontal")

        check(WheelSwipe.direction(delta: -3, now: 10, lastTick: 0) == .advance, "Negative delta advances")
        check(WheelSwipe.direction(delta: 3, now: 10, lastTick: 0) == .rewind, "Positive delta rewinds")
        check(WheelSwipe.direction(delta: -3, now: 10.2, lastTick: 10) == nil, "A tick inside the idle gap does not fire")
        check(WheelSwipe.direction(delta: -3, now: 10.5, lastTick: 10) == .advance, "A tick after the idle gap fires")

        // One flick that keeps ticking for longer than the idle gap is still
        // one gesture: the gap is measured from the previous tick, not from
        // the last page change.
        var lastTick: TimeInterval = 0
        var changes = 0
        for t in stride(from: 10.0, through: 10.9, by: 0.1) {
            if WheelSwipe.direction(delta: -3, now: t, lastTick: lastTick) != nil { changes += 1 }
            lastTick = t
        }
        check(changes == 1, "A continuous burst longer than the idle gap moves one page, got \(changes)")
        check(WheelSwipe.direction(delta: -3, now: 11.4, lastTick: lastTick) == .advance,
              "The next flick after an idle gap fires again")
        print("PASS \(checks) wheel swipe checks")
    }
}
