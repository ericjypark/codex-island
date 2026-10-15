import Foundation

@main
struct SparklineSamplesTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        let recordedHistories: [[Double]] = [[], [0], [0, 12, 73], [100, 80, 27]]
        for history in recordedHistories {
            let displayed = SparklineSamples.displayed(history: history, value: 67, seed: 4, isDemo: false)
            check(displayed == history, "Normal mode must display only the original recorded measurements")
        }

        let storedHistory = [10.0, 30.0, 90.0]
        for value in [0.0, 27.0, 73.0, 100.0] {
            let empty = SparklineSamples.displayed(history: [], value: value, seed: 0, isDemo: true)
            let existing = SparklineSamples.displayed(history: storedHistory, value: value, seed: 0, isDemo: true)
            check(empty.count >= 2, "A clean demo launch must have a drawable curve")
            check(empty == existing, "Demo mode must not expose existing real usage in its curve")
            check(empty.last == value, "The demo endpoint must agree with the displayed percentage")
            check(empty.allSatisfy { $0.isFinite && (0...100).contains($0) }, "Demo samples must stay in quota bounds")
            check(empty == SparklineSamples.displayed(history: [], value: value, seed: 0, isDemo: true),
                  "Redrawing the demo must not change its history")
            check(empty != SparklineSamples.displayed(history: [], value: value, seed: 1, isDemo: true),
                  "Different windows should have distinct sample curves")
        }
        check(storedHistory == [10, 30, 90], "Demo rendering must preserve supplied real history")
        print("PASS \(checks) sparkline sample checks")
    }
}
