import Combine
import Foundation

enum DisplayCurrency: String, CaseIterable, Codable, Identifiable {
    case usd = "USD"
    case cny = "CNY"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case krw = "KRW"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case sek = "SEK"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .usd: "$"
        case .cny, .jpy: "¥"
        case .eur: "€"
        case .gbp: "£"
        case .krw: "₩"
        case .cad: "C$"
        case .aud: "A$"
        case .chf: "CHF "
        case .sek: "SEK "
        }
    }

    func affixes(locale: Locale) -> (prefix: String, suffix: String) {
        guard self == .sek else { return (symbol, "") }
        let formatted = 1.0.formatted(.currency(code: rawValue).locale(locale).attributed)
        let numbers = formatted.runs.filter { $0.numberPart != nil }
        guard let first = numbers.first, let last = numbers.last else { return (symbol, "") }
        return (String(formatted.characters[..<first.range.lowerBound]),
                String(formatted.characters[last.range.upperBound...]))
    }

    var menuLabel: String { "\(rawValue)  \(symbol)" }
    var usesWholeUnits: Bool { self == .jpy || self == .krw }

    var colorClubThresholds: (black: Double, blue: Double) {
        switch self {
        case .usd, .eur, .gbp, .cad, .aud, .chf: (1_000, 10_000)
        case .cny, .sek: (10_000, 100_000)
        case .jpy: (100_000, 1_000_000)
        case .krw: (1_000_000, 10_000_000)
        }
    }
}

struct CurrencyQuote {
    let currency: DisplayCurrency
    let usdRate: Double
    let locale: Locale

    static var usd: CurrencyQuote { CurrencyQuote(currency: .usd, usdRate: 1) }

    init(currency: DisplayCurrency, usdRate: Double, locale: Locale = L10n.locale) {
        precondition(usdRate.isFinite && usdRate > 0)
        self.currency = currency
        self.usdRate = usdRate
        self.locale = locale
    }

    func converted(usd: Double) -> Double { usd * usdRate }

    func formatted(usd: Double) -> String {
        String(attributed(usd: usd).characters)
    }

    func attributed(usd: Double) -> AttributedString {
        let value = converted(usd: usd)
        let amount = max(0, value.isFinite ? value : 0)
        let minimum = currency.usesWholeUnits ? 1.0 : 0.01
        var style = FloatingPointFormatStyle<Double>.Currency(code: currency.rawValue).locale(locale)
        if amount > 0 && amount < minimum {
            return AttributedString("<") + minimum.formatted(style.attributed)
        }
        let precision = currency.usesWholeUnits ? 1.0 : 100.0
        let rounded = (amount * precision).rounded() / precision
        let nextMilestone = amount < 100 ? 100 : pow(10, floor(log10(amount)) + 1)
        if amount < nextMilestone, rounded >= nextMilestone, nextMilestone <= 1_000_000_000 {
            style = style.rounded(rule: .towardZero)
        }
        return amount.formatted(style.attributed)
    }

    func milestoneLabel(amount: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency.rawValue)
            .locale(locale).precision(.fractionLength(0))
        var formatted = amount.formatted(style.attributed)
        let numbers = formatted.runs.filter { $0.numberPart != nil }
        guard let first = numbers.first, let last = numbers.last else { return String(formatted.characters) }
        // Club abbreviations stay K/M/B while currency placement follows the locale.
        let compact = amount.formatted(FloatingPointFormatStyle<Double>.number
            .locale(Locale(identifier: "en_US")).precision(.fractionLength(0)).notation(.compactName))
        formatted.replaceSubrange(first.range.lowerBound..<last.range.upperBound, with: AttributedString(compact))
        return String(formatted.characters)
    }
}

@MainActor
final class CurrencyStore: ObservableObject {
    static let shared = CurrencyStore()

    private static let selectionKey = "MacIsland.displayCurrency"
    private static let cacheKey = "MacIsland.currencyRates.v2"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    private struct CachedRates: Codable {
        let rates: [String: Double]
        let fetchedAt: Date
        let sourceDate: String
    }

    private struct RateResponse: Decodable {
        let result: String
        let baseCode: String
        let timeLastUpdateUnix: TimeInterval
        let rates: [String: Double]

        enum CodingKeys: String, CodingKey {
            case result, rates
            case baseCode = "base_code"
            case timeLastUpdateUnix = "time_last_update_unix"
        }
    }

    @Published var currency: DisplayCurrency {
        didSet {
            defaults.set(currency.rawValue, forKey: Self.selectionKey)
        }
    }

    var usdRate: Double { cache?.rates[currency.rawValue] ?? 1 }
    var lastUpdated: Date? { cache?.fetchedAt }
    @Published private(set) var refreshing = false

    @Published private var cache: CachedRates?
    private let defaults: UserDefaults
    private var refreshTimer: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currency = defaults.string(forKey: Self.selectionKey)
            .flatMap(DisplayCurrency.init(rawValue:)) ?? .usd
        if let data = defaults.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode(CachedRates.self, from: data),
           Self.validRates(decoded.rates, requiringAllCurrencies: false) {
            cache = decoded
        } else {
            cache = nil
        }
    }

    func converted(usd: Double) -> Double {
        usd * usdRate
    }

    func quote(for currency: DisplayCurrency, locale: Locale = L10n.locale) -> CurrencyQuote? {
        if currency == .usd { return CurrencyQuote(currency: .usd, usdRate: 1, locale: locale) }
        guard let rate = cache?.rates[currency.rawValue] else { return nil }
        return CurrencyQuote(currency: currency, usdRate: rate, locale: locale)
    }

    var displayCurrency: DisplayCurrency {
        hasUsableRate ? currency : .usd
    }

    var displaySymbol: String {
        displayCurrency.symbol
    }

    var displayPrefix: String { displayCurrency.affixes(locale: L10n.locale).prefix }
    var displaySuffix: String { displayCurrency.affixes(locale: L10n.locale).suffix }

    var displayUsesWholeUnits: Bool {
        displayCurrency.usesWholeUnits
    }

    private var hasUsableRate: Bool {
        currency == .usd || cache?.rates[currency.rawValue] != nil
    }

    func formatted(usd: Double, compact: Bool = true, includesSymbol: Bool = true,
                   abbreviated: Bool = false, locale: Locale = L10n.locale) -> String {
        let number = DisplayNumber.money(converted(usd: usd), wholeUnits: displayUsesWholeUnits,
            compact: compact, abbreviated: abbreviated, locale: locale)
        let affixes = displayCurrency.affixes(locale: locale)
        return includesSymbol ? affixes.prefix + number + affixes.suffix : number
    }

    func refresh() {
        Task { await refreshIfNeeded(force: true) }
    }

    func startAutoRefresh() {
        Task { await refreshIfNeeded() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshIfNeeded() }
        }
    }

    private static func validRates(_ rates: [String: Double], requiringAllCurrencies: Bool = true) -> Bool {
        guard rates["USD"] == 1 else { return false }
        return DisplayCurrency.allCases.allSatisfy {
            guard let rate = rates[$0.rawValue] else { return !requiringAllCurrencies }
            return rate.isFinite && rate > 0
        }
    }

    func refreshIfNeeded(
        force: Bool = false,
        now: Date = Date(),
        fetch: (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) async {
        guard !refreshing else { return }
        if !force, let cache,
           now.timeIntervalSince(cache.fetchedAt) < Self.refreshInterval {
            return
        }

        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        refreshing = true
        defer { refreshing = false }
        do {
            let (data, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(RateResponse.self, from: data),
                  decoded.result == "success",
                  decoded.baseCode == "USD",
                  Self.validRates(decoded.rates) else { return }
            let sourceDate = ISO8601DateFormatter().string(
                from: Date(timeIntervalSince1970: decoded.timeLastUpdateUnix)
            )
            cache = CachedRates(rates: decoded.rates, fetchedAt: now, sourceDate: sourceDate)
            persistCache()
        } catch {
            // Keep the most recent cached rate. Currency display should remain
            // stable when the Mac is offline or the reference API is down.
        }
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }
}
