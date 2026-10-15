import Foundation

/// Locks down payload validation and the in-memory store: what the app is
/// willing to believe from the network, and that a rejection never mutates
/// what it already has.
@main
struct PricingCatalogTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    static func json(_ raw: String) -> Data { Data(raw.utf8) }

    static let valid = """
    {"schemaVersion":1,"generatedAt":"2026-07-26T01:00:00Z","models":{
      "claude-opus-4-8":{"displayName":"Opus 4.8","inputPerMillion":5,
        "outputPerMillion":25,"cacheCreationPerMillion":6.25,"cacheReadPerMillion":0.5}}}
    """

    static func main() async {
        // Every disk write in this file goes to a temp path. Without the
        // explicit `cache:`, refreshIfNeeded defaults to the real cache and
        // the suite silently overwrites the user's installed catalog.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codexisland-catalog-test.json")
        try? FileManager.default.removeItem(at: tmp)

        // A well-formed v1 payload is accepted and decoded.
        if case .payload(let p) = PricingCatalog.interpret(status: 200, data: json(valid)) {
            expect(p.models.count == 1, "valid payload decodes one model")
            expect(p.models["claude-opus-4-8"]?.inputPerMillion == 5, "rates decode")
            expect(p.models["claude-opus-4-8"]?.displayName == "Opus 4.8", "displayName decodes")
        } else {
            expect(false, "valid payload accepted")
        }

        expect(PricingCatalog.interpret(status: 304, data: Data()) == .unchanged,
               "304 reports unchanged")

        // Everything below must be rejected — each one would otherwise zero
        // out or corrupt the user's dollar totals.
        let rejects: [(String, CatalogFetchResult)] = [
            ("HTTP 500", PricingCatalog.interpret(status: 500, data: json(valid))),
            ("HTTP 404", PricingCatalog.interpret(status: 404, data: Data())),
            ("malformed JSON", PricingCatalog.interpret(status: 200, data: json("{nope"))),
            ("wrong schema", PricingCatalog.interpret(
                status: 200,
                data: json(#"{"schemaVersion":2,"generatedAt":"x","models":{"a":{"inputPerMillion":1,"outputPerMillion":1,"cacheCreationPerMillion":1,"cacheReadPerMillion":1}}}"#))),
            ("empty catalog", PricingCatalog.interpret(
                status: 200,
                data: json(#"{"schemaVersion":1,"generatedAt":"x","models":{}}"#))),
        ]
        for (label, result) in rejects {
            if case .rejected = result { print("PASS rejects \(label)") }
            else { print("FAIL rejects \(label)"); failures += 1 }
        }

        // displayName is optional — a payload without it still decodes.
        if case .payload(let p) = PricingCatalog.interpret(
            status: 200,
            data: json(#"{"schemaVersion":1,"generatedAt":"x","models":{"gpt-9":{"inputPerMillion":1,"outputPerMillion":2,"cacheCreationPerMillion":1,"cacheReadPerMillion":0}}}"#)
        ) {
            expect(p.models["gpt-9"]?.displayName == nil, "absent displayName decodes as nil")
        } else {
            expect(false, "payload without displayName accepted")
        }

        // Store round trip.
        expect(PricingCatalog.lastFetched == nil, "store starts empty")
        expect(PricingCatalog.rates(for: "claude-opus-4-8") == nil, "empty store returns nil")

        // Runs before anything installs, because `lastFetched` is nil only on
        // a fresh process — and that is the branch a new install takes. A
        // guard that bailed out when nothing had ever been fetched would mean
        // the app never fetches a catalog at all, and every other assertion
        // in this file would still pass. The transport throws, so the store
        // is left exactly as it was.
        var firstRunRequests = 0
        await PricingCatalog.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1_000_000), cache: tmp
        ) { _ in
            firstRunRequests += 1
            throw URLError(.notConnectedToInternet)
        }
        expect(firstRunRequests == 1, "a never-fetched catalog refreshes on first run")

        let stamp = Date(timeIntervalSince1970: 1_784_000_000)
        PricingCatalog.install(
            models: ["claude-opus-4-8": CatalogRates(
                displayName: "Opus 4.8", inputPerMillion: 5, outputPerMillion: 25,
                cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.5)],
            fetchedAt: stamp
        )
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.outputPerMillion == 25,
               "installed rates are readable")
        expect(PricingCatalog.lastFetched == stamp, "install records the fetch time")
        expect(PricingCatalog.rates(for: "not-a-model") == nil, "unknown id returns nil")

        // Installing replaces wholesale rather than merging.
        PricingCatalog.install(models: ["gpt-5.6": CatalogRates(
            displayName: nil, inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.5)], fetchedAt: stamp)
        expect(PricingCatalog.rates(for: "claude-opus-4-8") == nil,
               "install replaces the whole table")

        // Refresh: a 200 installs, and the transport sees no If-None-Match
        // until an ETag has been stored.
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        var seenHeaders: [String?] = []

        func transport(_ status: Int, _ body: Data, _ etag: String?)
            -> (URLRequest) async throws -> (Data, URLResponse) {
            { req in
                seenHeaders.append(req.value(forHTTPHeaderField: "If-None-Match"))
                var fields: [String: String] = [:]
                if let etag { fields["ETag"] = etag }
                let resp = HTTPURLResponse(
                    url: PricingCatalog.endpoint, statusCode: status,
                    httpVersion: nil, headerFields: fields)!
                return (body, resp)
            }
        }

        PricingCatalog.install(models: [:], fetchedAt: Date(timeIntervalSince1970: 0))
        await PricingCatalog.refreshIfNeeded(
            now: base, cache: tmp, fetch: transport(200, json(valid), "\"abc\""))
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "200 installs the payload")
        expect(PricingCatalog.lastFetched == base, "200 records the fetch time")

        // Within 24h the refresh is a no-op — no request at all.
        let before = seenHeaders.count
        await PricingCatalog.refreshIfNeeded(
            now: base.addingTimeInterval(3_600), cache: tmp, fetch: transport(200, Data(), nil))
        expect(seenHeaders.count == before, "refresh inside 24h makes no request")

        // Past 24h it fetches again, now carrying the stored ETag.
        let later = base.addingTimeInterval(25 * 3_600)
        await PricingCatalog.refreshIfNeeded(now: later, cache: tmp, fetch: transport(304, Data(), nil))
        expect(seenHeaders.last == "\"abc\"", "stored ETag is sent as If-None-Match")
        expect(PricingCatalog.lastFetched == later, "304 advances the fetch time")
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "304 preserves the payload")

        // A garbage response must not disturb what is already installed.
        let later2 = later.addingTimeInterval(25 * 3_600)
        await PricingCatalog.refreshIfNeeded(now: later2, cache: tmp, fetch: transport(200, json("{nope"), nil))
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "malformed payload leaves the catalog intact")
        expect(PricingCatalog.lastFetched == later, "rejected payload does not advance the clock")

        // A transport that throws is equally harmless.
        await PricingCatalog.refreshIfNeeded(now: later2, cache: tmp, fetch: { _ in
            throw URLError(.notConnectedToInternet)
        })
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "network failure leaves the catalog intact")

        // Disk cache: the middle tier of the fallback ladder. Round-trips
        // through a temp file so the user's real cache is never touched.

        guard case .payload(let diskPayload) =
            PricingCatalog.interpret(status: 200, data: json(valid)) else {
            expect(false, "fixture payload parses")
            exit(1)
        }
        PricingCatalog.persist(diskPayload, etag: "\"disk\"", at: base, to: tmp)

        // Clobber the in-memory ETag without touching the file — `to: nil`
        // writes nothing. Without this, `loadFromDisk` reassigning the same
        // value it already holds is unobservable, and both halves of "the
        // ETag lives with the payload on disk" could be deleted with a green
        // suite.
        PricingCatalog.persist(diskPayload, etag: "\"memory\"", at: base, to: nil)

        PricingCatalog.install(models: [:], fetchedAt: Date(timeIntervalSince1970: 0))
        expect(PricingCatalog.rates(for: "claude-opus-4-8") == nil, "store cleared before load")

        PricingCatalog.loadFromDisk(from: tmp)
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "cached payload loads from disk")
        expect(PricingCatalog.lastFetched == base, "cached fetch time is restored")

        // The ETag has to come back off disk with its payload. If it does not,
        // the app can hold an ETag for a cache it no longer has, receive 304
        // for data it does not hold, and sit on the embedded seed forever.
        var diskHeaders: [String?] = []
        await PricingCatalog.refreshIfNeeded(
            now: base.addingTimeInterval(60 * 86_400), cache: tmp
        ) { req in
            diskHeaders.append(req.value(forHTTPHeaderField: "If-None-Match"))
            throw URLError(.cancelled)
        }
        expect(diskHeaders.last == "\"disk\"", "ETag restored from disk is sent as If-None-Match")

        // A cache whose model map is empty must be ignored, not adopted —
        // adopting it would price every model at $0.
        PricingCatalog.persist(
            CatalogPayload(schemaVersion: 1, generatedAt: "x", models: [:]),
            etag: nil, at: base, to: tmp)
        PricingCatalog.loadFromDisk(from: tmp)
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "empty-model cache is ignored, previous state survives")

        // Same for a file that is not JSON at all.
        try? Data("not json".utf8).write(to: tmp)
        PricingCatalog.loadFromDisk(from: tmp)
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "corrupt cache file is ignored, previous state survives")

        // A 304 must carry its timestamp to disk, not just to memory. Without
        // that, a restart restores the older stamp — and since a stable
        // catalog answers almost every refresh with 304, the staleness figure
        // would climb for a user whose prices are simply not changing.
        PricingCatalog.persist(diskPayload, etag: "\"disk\"", at: base, to: tmp)
        PricingCatalog.loadFromDisk(from: tmp)
        let verified = base.addingTimeInterval(90 * 86_400)
        await PricingCatalog.refreshIfNeeded(now: verified, cache: tmp) { _ in
            (Data(), HTTPURLResponse(
                url: PricingCatalog.endpoint, statusCode: 304,
                httpVersion: nil, headerFields: [:])!)
        }
        PricingCatalog.install(models: [:], fetchedAt: Date(timeIntervalSince1970: 0))
        PricingCatalog.loadFromDisk(from: tmp)
        expect(PricingCatalog.lastFetched == verified,
               "304 timestamp survives a reload from disk")
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "304 leaves the cached payload alone")

        // A cache written by a future schema is ignored rather than trusted.
        let futureSchema = CatalogPayload(
            schemaVersion: 2, generatedAt: "x",
            models: ["claude-opus-4-8": CatalogRates(
                displayName: nil, inputPerMillion: 999, outputPerMillion: 999,
                cacheCreationPerMillion: 999, cacheReadPerMillion: 999)])
        PricingCatalog.persist(futureSchema, etag: nil, at: base, to: tmp)
        PricingCatalog.loadFromDisk(from: tmp)
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "future-schema cache is ignored, previous state survives")

        // A missing file is a no-op, not a crash or a wipe.
        try? FileManager.default.removeItem(at: tmp)
        PricingCatalog.loadFromDisk(from: tmp)
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "missing cache file leaves the store alone")

        exit(failures == 0 ? 0 : 1)
    }
}
