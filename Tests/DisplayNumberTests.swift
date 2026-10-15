import Foundation

@main
struct DisplayNumberTests {
    static func main() {
        let locale = Locale(identifier: "en_US")
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        for used in 0...100 {
            let fraction = Double(used) / 100
            check(DisplayNumber.percent(fraction * 100) == used, "Used \(used) must survive normalization")
            check(DisplayNumber.percent((1 - fraction) * 100) == 100 - used,
                  "Remaining \(100 - used) must survive subtraction")
        }
        for (value, expected) in [(-1.0, 0), (0.49, 0), (0.5, 1), (9.5, 10),
                                  (69.5, 70), (89.5, 90), (99.5, 100), (101.0, 100)] {
            check(DisplayNumber.percent(value) == expected, "Rounded/clamped percentage \(value)")
        }
        for (input, expected) in [(999, "999tok"), (1_000, "1k"), (9_999, "10k"), (10_000, "10k"),
                                  (999_500, "999.5k"), (999_949, "999.9k"), (999_950, "1M"),
                                  (999_999, "1M"), (1_000_000, "1M"), (999_999_999, "1B"),
                                  (1_000_000_000, "1B"), (Int.max, "9.2E")] {
            let result = DisplayNumber.tokens(input, locale: locale)
            check(result.value + result.unit == expected, "Token boundary \(input)")
        }
        for (value, expected) in [(0.0, "0"), (9.99, "9.99"), (10, "10"), (99.99, "100"),
                                  (100, "100"), (999.49, "999"), (999.5, "1k"),
                                  (1_000, "1k"), (999_950, "1M"), (1_000_000, "1M")] {
            check(DisplayNumber.money(value, wholeUnits: false, abbreviated: true, locale: locale) == expected,
                  "Money boundary \(value)")
        }
        check(DisplayNumber.money(1_234.5, wholeUnits: false, compact: false, locale: locale) == "1,234.50",
              "Full money must retain cents and grouping")
        check(DisplayNumber.money(130_000, wholeUnits: true, compact: false, locale: locale) == "130,000",
              "Whole-unit currencies must stay whole")
        check(DisplayNumber.money(130_000, wholeUnits: true, abbreviated: true, locale: locale) == "130k",
              "Whole-unit currencies may use equivalent compact units")
        let localized = DisplayNumber.tokens(1_234, locale: Locale(identifier: "fr_FR"))
        check(localized.value == "1,2", "Compact digits must honor the selected locale")
        print("PASS \(checks) numeric display boundary checks")
    }
}
