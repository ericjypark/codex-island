import Foundation

// A pacing request, not a guarantee: macOS still schedules presentation.
enum ExpandedFrameRate {
    static func preferred(maximum: Int, lowPower: Bool) -> Int {
        let supported = maximum > 0 ? maximum : 60
        return min(supported, lowPower ? 30 : 120)
    }
}
