import Foundation

@main
struct WheelSwipeTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        func decide(_ dx: CGFloat, _ dy: CGFloat, shift: Bool = false,
                    now: TimeInterval = 10, last: TimeInterval = 0) -> WheelSwipe.Direction? {
            WheelSwipe.direction(deltaX: dx, deltaY: dy, shift: shift, now: now, lastChange: last)
        }
        check(decide(-3, 0) == .advance, "Negative horizontal delta advances")
        check(decide(3, 0) == .rewind, "Positive horizontal delta rewinds")
        check(decide(-1, 0.4) == .advance, "Slight vertical noise does not block a horizontal tick")
        check(decide(0, -3) == nil, "Vertical wheel tick without Shift is not a page change")
        check(decide(-0.3, 0) == nil, "Sub-threshold horizontal delta is ignored")
        check(decide(0, -3, shift: true) == .advance, "Shift+vertical wheel advances")
        check(decide(0, 3, shift: true) == .rewind, "Shift+vertical wheel rewinds")
        check(decide(-3, 0, shift: true) == .advance, "Shift with swapped axis still reads horizontal")
        check(decide(-3, 0, now: 10.2, last: 10) == nil, "Ticks within the debounce window are ignored")
        check(decide(-3, 0, now: 10.5, last: 10) == .advance, "A tick after the debounce window fires")
        check(decide(0, -3, shift: true, now: 10.1, last: 10) == nil, "Shift ticks are debounced too")
        print("PASS \(checks) wheel swipe checks")
    }
}
