import Foundation

enum DisplayNumber {
    static func percent(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }

    static func tokens(_ value: Int, locale: Locale) -> (value: String, unit: String) {
        if value < 1_000 { return (format(Double(value), digits: 0, locale: locale), "tok") }
        return abbreviated(Double(value), locale: locale)
    }

    static func money(_ value: Double, wholeUnits: Bool, compact: Bool = true,
                      abbreviated: Bool = false, locale: Locale) -> String {
        if abbreviated, abs(value).rounded() >= 1_000 {
            let parts = self.abbreviated(abs(value) < 1_000 ? value.rounded() : value, locale: locale)
            return parts.value + parts.unit
        }
        let digits = wholeUnits ? 0 : !compact ? 2 : abs(value) >= 100 ? 0 : abs(value) >= 10 ? 1 : 2
        return format(value, digits: digits, minimumDigits: compact ? 0 : digits,
                      grouping: true, locale: locale)
    }

    private static func abbreviated(_ value: Double, locale: Locale) -> (value: String, unit: String) {
        let units = ["", "k", "M", "B", "T", "P", "E"]
        var scaled = value
        var index = 0
        while abs(scaled) >= 1_000, index < units.count - 1 {
            scaled /= 1_000
            index += 1
        }
        if (abs(scaled) * 10).rounded() / 10 >= 1_000, index < units.count - 1 {
            scaled /= 1_000
            index += 1
        }
        return (format(scaled, digits: 1, locale: locale), units[index])
    }

    private static func format(_ value: Double, digits: Int, minimumDigits: Int = 0,
                               grouping: Bool = false, locale: Locale) -> String {
        value.formatted(.number.locale(locale).grouping(grouping ? .automatic : .never)
            .precision(.fractionLength(minimumDigits...digits)))
    }
}
