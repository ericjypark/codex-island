import Foundation

enum UsageCreditDisplay {
    static func compactCurrency(_ amount: Double, code: String?, locale: Locale = L10n.locale) -> String {
        guard abs(amount) >= 1_000 else { return currency(amount, code: code, locale: locale) }
        let units = ["k", "M", "B", "T", "P", "E"]
        var scaled = amount / 1_000
        var index = 0
        while abs(scaled).rounded() >= 1_000, index < units.count - 1 {
            scaled /= 1_000
            index += 1
        }
        let currency = NumberFormatter()
        currency.locale = locale
        currency.numberStyle = .currency
        currency.currencyCode = code ?? "USD"
        let number = NumberFormatter()
        number.locale = locale
        number.numberStyle = .decimal
        number.maximumFractionDigits = 1
        number.usesGroupingSeparator = false
        let value = number.string(from: NSNumber(value: scaled)) ?? "\(scaled)"
        return currency.positivePrefix + value + units[index] + currency.positiveSuffix
    }

    static func currency(_ amount: Double, code: String?, locale: Locale = L10n.locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code ?? "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}

extension WindowUsage {
    var amountCaption: String? {
        guard let usedAmount else { return nil }
        let used = UsageCreditDisplay.currency(usedAmount, code: currencyCode)
        if let limitAmount {
            return L10n.tr("%@ / %@ credits used", used,
                           UsageCreditDisplay.currency(limitAmount, code: currencyCode))
        }
        return L10n.tr("%@ credits used · unlimited", used)
    }
}

extension UsageWindow {
    var labelKey: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "week"
        case .monthly: return "Credits"
        }
    }
}
