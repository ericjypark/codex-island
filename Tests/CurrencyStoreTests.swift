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
            (.chf, "de_CH", "CHF 1’000.00"),
            (.sek, "sv_SE", "1 000,00 kr"), (.sek, "en_US", "SEK 1,000.00")
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
        precondition(germanEuro.milestoneLabel(amount: 1_000_000) == "1M €")
        let badges: [(DisplayCurrency, String, String)] = [
            (.krw, "ko_KR", "₩1M"), (.cny, "zh_CN", "¥1M"), (.jpy, "ja_JP", "¥1M"),
            (.eur, "de_DE", "1M €"), (.sek, "sv_SE", "1M kr"), (.cad, "fr_CA", "1M $")
        ]
        for (currency, identifier, expected) in badges {
            let quote = CurrencyQuote(currency: currency, usdRate: 1, locale: Locale(identifier: identifier))
            precondition(quote.milestoneLabel(amount: 1_000_000) == expected,
                         "Club abbreviations stay K/M/B in \(identifier)")
        }
        let wonBadge = CurrencyQuote(currency: .krw, usdRate: 1, locale: Locale(identifier: "ko_KR"))
        for (amount, label) in [(100.0, "₩100"), (1_000, "₩1K"), (10_000, "₩10K"),
                               (100_000, "₩100K"), (1_000_000, "₩1M"), (10_000_000, "₩10M"),
                               (100_000_000, "₩100M"), (1_000_000_000, "₩1B")] {
            precondition(wonBadge.milestoneLabel(amount: amount) == label)
        }
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
         "rates":{"USD":1,"EUR":0.9,"GBP":0.8,"CNY":7,"JPY":150,"KRW":1300,"CAD":1.3,"AUD":1.5,"CHF":0.85,"SEK":10.5}}
        """.utf8)
        let oldCache: [String: Any] = [
            "rates": ["USD": 1, "EUR": 0.9, "GBP": 0.8, "CNY": 7, "JPY": 150,
                      "KRW": 1300, "CAD": 1.3, "AUD": 1.5, "CHF": 0.85],
            "fetchedAt": Date().timeIntervalSinceReferenceDate, "sourceDate": "2026-09-29"
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: oldCache), forKey: "MacIsland.currencyRates.v2")
        defaults.set("EUR", forKey: "MacIsland.displayCurrency")
        let upgraded = CurrencyStore(defaults: defaults)
        await upgraded.refreshIfNeeded(force: true) { _ in throw URLError(.notConnectedToInternet) }
        precondition(upgraded.lastUpdated != nil && upgraded.converted(usd: 100) == 90)
        precondition(upgraded.displayCurrency == .eur)
        precondition(upgraded.quote(for: .eur)?.converted(usd: 100) == 90)
        precondition(upgraded.quote(for: .sek) == nil)
        upgraded.currency = .sek
        precondition(upgraded.displayCurrency == .usd && upgraded.converted(usd: 100) == 100)
        upgraded.currency = .gbp
        precondition(upgraded.displayCurrency == .gbp && upgraded.converted(usd: 100) == 80)
        var invalidCache = oldCache
        invalidCache["rates"] = ["USD": 1, "EUR": -0.9]
        defaults.set(try JSONSerialization.data(withJSONObject: invalidCache), forKey: "MacIsland.currencyRates.v2")
        precondition(CurrencyStore(defaults: defaults).lastUpdated == nil)
        defaults.removeObject(forKey: "MacIsland.currencyRates.v2")
        defaults.removeObject(forKey: "MacIsland.displayCurrency")
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
        store.currency = .sek
        let compactKrona = store.formatted(usd: 100, abbreviated: true, locale: Locale(identifier: "sv_SE"))
        precondition(compactKrona.hasSuffix(" kr") && !compactKrona.hasPrefix("kr"))
        store.currency = .eur
        let compactEuro = store.formatted(usd: 2_000_000, abbreviated: true, locale: Locale(identifier: "de_DE"))
        precondition(compactEuro == "€1,8M")
        store.currency = .usd
        precondition(store.formatted(usd: 9.5, compact: false, locale: english) == "$9.50")
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
        store.currency = .sek
        precondition(store.displayCurrency == .sek && store.converted(usd: 100) == 1050)
        precondition(store.quote(for: .sek)?.converted(usd: 100) == 1050)
        precondition(store.displaySymbol == "SEK " && !store.displayUsesWholeUnits)
        let swedish = Locale(identifier: "sv_SE")
        precondition(store.formatted(usd: 1, compact: false, locale: swedish) == "10,50 kr")
        precondition(store.formatted(usd: 1, compact: false, includesSymbol: false, locale: swedish) == "10,50")
        precondition(store.formatted(usd: 1, compact: false, locale: english) == "SEK 10.50")
        precondition(DisplayCurrency.sek.affixes(locale: swedish).prefix.isEmpty)
        precondition(DisplayCurrency.sek.affixes(locale: swedish).suffix == " kr")
        store.currency = .usd
        precondition(store.usdRate == 1 && store.displaySymbol == "$")
        print("PASS currency switching, single-flight refresh, expiry, offline retention, validation, persistence, manual refresh")
    }
}
