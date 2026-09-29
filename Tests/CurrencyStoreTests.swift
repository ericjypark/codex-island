import Foundation

@main
struct CurrencyStoreTests {
    @MainActor static func main() async throws {
        let english = Locale(identifier: "en_US")
        let cases: [(DisplayCurrency, String, String)] = [
            (.usd, "en_US", "$1,000.00"), (.krw, "ko_KR", "₩1,000"),
            (.cny, "zh_CN", "¥1,000.00"), (.jpy, "ja_JP", "¥1,000"),
            (.gbp, "en_GB", "£1,000.00"), (.aud, "en_AU", "$1,000.00"),
            (.cad, "en_CA", "$1,000.00"), (.cad, "fr_CA", "1 000,00 $"),
            (.eur, "en_US", "€1,000.00"), (.eur, "de_DE", "1.000,00 €"),
            (.chf, "de_CH", "CHF 1’000.00")
        ]
        for (currency, identifier, expected) in cases {
            let quote = CurrencyQuote(currency: currency, usdRate: 1, locale: Locale(identifier: identifier))
            precondition(quote.formatted(usd: 1_000) == expected, "\(currency) in \(identifier)")
            let integers = quote.attributed(usd: 1_000).runs.filter { $0.numberPart == .integer }
            precondition(!integers.isEmpty)
        }
        let germanEuro = CurrencyQuote(currency: .eur, usdRate: 1, locale: Locale(identifier: "de_DE"))
        precondition(germanEuro.formatted(usd: 0.001) == "<0,01 €")
        precondition(germanEuro.formatted(usd: 999.999) == "999,99 €")
        precondition(germanEuro.milestoneLabel(amount: 1_000_000) == "1 Mio. €")
        let canadianBadge = CurrencyQuote(currency: .cad, usdRate: 1, locale: Locale(identifier: "fr_CA"))
            .milestoneLabel(amount: 1_000_000)
        precondition(canadianBadge.contains("M") && canadianBadge.hasSuffix("$") && !canadianBadge.hasPrefix("$"))
        let suite = "CurrencyStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite),
              let url = URL(string: "https://example.com/rates"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { fatalError("Test setup failed") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("""
        {"result":"success","base_code":"USD","time_last_update_unix":1700000000,
         "rates":{"USD":1,"EUR":0.9,"GBP":0.8,"CNY":7,"JPY":150,"KRW":1300,"CAD":1.3,"AUD":1.5,"CHF":0.85}}
        """.utf8)
        let store = CurrencyStore(defaults: defaults)
        let now = Date()
        store.currency = .eur
        precondition(store.displayCurrency == .usd && store.converted(usd: 100) == 100)

        var requests = 0
        await store.refreshIfNeeded(now: now) { _ in
            requests += 1
            store.currency = .gbp
            await store.refreshIfNeeded(force: true) { _ in
                fatalError("Concurrent refresh must be coalesced")
            }
            precondition(store.refreshing)
            return (data, response)
        }
        precondition(requests == 1 && !store.refreshing)
        precondition(store.displayCurrency == .gbp && store.converted(usd: 100) == 80)
        precondition(store.quote(for: .eur, locale: english)?.formatted(usd: 100) == "€90.00")
        precondition(store.quote(for: .jpy, locale: english)?.formatted(usd: 100) == "¥15,000")
        precondition(store.quote(for: .usd, locale: english)?.formatted(usd: 100) == "$100.00")
        precondition(store.quote(for: .krw, locale: english)?.formatted(usd: 100) == "₩130,000")
        precondition(store.quote(for: .eur, locale: english)?.formatted(usd: 0.001) == "<€0.01")
        precondition(store.quote(for: .krw, locale: english)?.formatted(usd: 0.0001) == "<₩1")
        store.currency = .krw
        precondition(store.converted(usd: 100) == 130000)
        precondition(store.displayUsesWholeUnits)
        await store.refreshIfNeeded(now: now.addingTimeInterval(23 * 3600)) { _ in
            fatalError("Fresh table must not fetch")
        }
        await store.refreshIfNeeded(now: now.addingTimeInterval(24 * 3600)) { _ in
            requests += 1
            throw URLError(.notConnectedToInternet)
        }
        precondition(requests == 2 && store.lastUpdated == now)
        precondition(store.converted(usd: 100) == 130000)
        await store.refreshIfNeeded(force: true) { _ in
            (Data("{}".utf8), response)
        }
        precondition(store.lastUpdated == now)
        let incomplete = Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"GBP\":0.8,", with: "").utf8)
        await store.refreshIfNeeded(force: true) { _ in (incomplete, response) }
        precondition(store.converted(usd: 100) == 130000 && store.lastUpdated == now)
        let restored = CurrencyStore(defaults: defaults)
        precondition(restored.currency == .krw && restored.converted(usd: 100) == 130000)
        precondition(restored.lastUpdated == now)
        await store.refreshIfNeeded(force: true, now: now.addingTimeInterval(60)) { _ in
            requests += 1
            return (data, response)
        }
        precondition(requests == 3 && store.lastUpdated == now.addingTimeInterval(60))
        store.currency = .usd
        precondition(store.usdRate == 1 && store.displaySymbol == "$")
        print("PASS currency switching, single-flight refresh, expiry, offline retention, validation, persistence, manual refresh")
    }
}
