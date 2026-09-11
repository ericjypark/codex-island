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
        }
    }

    var menuLabel: String { "\(rawValue)  \(symbol)" }
    var usesWholeUnits: Bool { self == .jpy || self == .krw }
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
           Self.validRates(decoded.rates) {
            cache = decoded
        } else {
            cache = nil
        }
    }

    func converted(usd: Double) -> Double {
        usd * usdRate
    }

    var displayCurrency: DisplayCurrency {
        hasUsableRate ? currency : .usd
    }

    var displaySymbol: String {
        displayCurrency.symbol
    }

    var displayUsesWholeUnits: Bool {
        displayCurrency.usesWholeUnits
    }

    private var hasUsableRate: Bool {
        currency == .usd || cache?.rates[currency.rawValue] != nil
    }

    func formatted(usd: Double, compact: Bool = true, includesSymbol: Bool = true) -> String {
        let value = converted(usd: usd)
        let digits: Int
        if displayUsesWholeUnits || value >= 100 {
            digits = 0
        } else if compact, value >= 10 {
            digits = 1
        } else {
            digits = 2
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = L10n.locale
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.usesGroupingSeparator = true
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return includesSymbol ? displaySymbol + number : number
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

    private static func validRates(_ rates: [String: Double]) -> Bool {
        rates["USD"] == 1 && DisplayCurrency.allCases.allSatisfy {
            guard let rate = rates[$0.rawValue] else { return false }
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
