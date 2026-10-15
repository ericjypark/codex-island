# Model Catalog App Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CodexIsland read model prices from the published catalog, falling back through a disk cache to the embedded table, so a new model no longer needs an app release.

**Architecture:** A new `PricingCatalog` holds the remote price table behind a lock, loads a disk cache at launch, and refreshes over HTTP with `If-None-Match` once a day. `Pricing` keeps its synchronous static API — every call site is untouched — but now consults the catalog before its own table, which is demoted to a build-time seed.

**Tech Stack:** Swift 5 (plain `swiftc`, no SPM/XCTest), Foundation, macOS 13+.

**Spec:** `docs/superpowers/specs/2026-07-26-model-list-api-design.md`

**Companion plan:** `2026-07-26-model-catalog-service.md` publishes the endpoint. This plan can be built and tested before that one ships — every test injects its payload, and at runtime the app just stays on its seed until the URL is live.

## Global Constraints

- **Working repo:** `codex-island`. This plan does **not** touch the catalog repo.
- **Endpoint:** `https://ericjypark.github.io/codex-island-model-catalog/v1/models.json`
- **Supported schema version is 1.** Any other value is rejected and the current state is kept.
- **A failed refresh must never change prices.** Network error, non-200, malformed JSON, wrong schema, or an empty model map all leave the existing catalog in place.
- **Call sites do not change.** `CostSummary`, `StatCardSummary`, and `CostBlock` must compile untouched.
- **The catalog store is lock-guarded.** `CostStore` calls `CostSummary.summarize` from two concurrent `Task.detached` blocks (`Sources/Cost/CostStore.swift:67`, `:77`), so `Pricing.cost(for:)` is read off the main actor while the refresh installs a new catalog.
- **Tests:** bare `swiftc` via `scripts/run-tests.sh`. No XCTest, no SPM. Harness idiom: `@main struct XTests` with `static var failures`, an `expect(_:_:)` helper, and `exit(failures == 0 ? 0 : 1)`.
- **`build.sh` needs no edit** — it globs `find Sources -name '*.swift'` (`build.sh:49`).
- **Commits:** Conventional Commits. Never add `Co-Authored-By` lines.
- **Comments:** default to none. Only explain a WHY that is not obvious.

---

### Task 1: Catalog types, payload validation, and the lock-guarded store

**Files:**
- Create: `Sources/Cost/PricingCatalog.swift`
- Create: `Tests/PricingCatalogTests.swift`
- Modify: `scripts/run-tests.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct CatalogRates: Codable, Equatable` — `displayName: String?`, `inputPerMillion`, `outputPerMillion`, `cacheCreationPerMillion`, `cacheReadPerMillion` (all `Double`)
  - `struct CatalogPayload: Codable, Equatable` — `schemaVersion: Int`, `generatedAt: String`, `models: [String: CatalogRates]`
  - `enum CatalogFetchResult: Equatable` — `.payload(CatalogPayload)`, `.unchanged`, `.rejected(String)`
  - `enum PricingCatalog` with `static func interpret(status: Int, data: Data) -> CatalogFetchResult`, `static func install(models: [String: CatalogRates], fetchedAt: Date)`, `static func rates(for canonical: String) -> CatalogRates?`, `static var lastFetched: Date?`

`etag` storage and `markVerified(at:)` belong to Task 2, which is what consumes
them. Declaring them here would land untested dead code — and dead code inside
the one file whose correctness argument is "every accessor takes the lock" is
exactly where it should not sit.

- [ ] **Step 1: Write the failing test**

Create `Tests/PricingCatalogTests.swift`:

```swift
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

    static func main() {
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

        exit(failures == 0 ? 0 : 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Add the target to `scripts/run-tests.sh`, appending at the end of the file:

```bash
swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-catalog-tests" \
  Sources/Cost/PricingCatalog.swift \
  Tests/PricingCatalogTests.swift

"$OUT_DIR/pricing-catalog-tests"
```

Run: `./scripts/run-tests.sh`

Expected: FAIL at compilation — `cannot find 'PricingCatalog' in scope`.

- [ ] **Step 3: Write the types and the store**

Create `Sources/Cost/PricingCatalog.swift`:

```swift
import Foundation

struct CatalogRates: Codable, Equatable {
    let displayName: String?
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheCreationPerMillion: Double
    let cacheReadPerMillion: Double
}

struct CatalogPayload: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let models: [String: CatalogRates]
}

enum CatalogFetchResult: Equatable {
    case payload(CatalogPayload)
    case unchanged
    case rejected(String)
}

/// Remote model price table, refreshed daily from the published catalog.
///
/// `Pricing` reads this before its own embedded seed, so anything installed
/// here decides what the user is charged on screen. Every path that fails to
/// produce a complete, current payload therefore leaves the previous state
/// untouched rather than installing something partial.
enum PricingCatalog {
    static let supportedSchemaVersion = 1

    /// Literal, known-good URL — the same force-unwrap idiom `UsageFetcher`
    /// uses for its endpoints.
    static let endpoint = URL(
        string: "https://ericjypark.github.io/codex-island-model-catalog/v1/models.json"
    )!

    /// `CostStore` summarizes on two concurrent detached tasks, so reads land
    /// off the main actor while a refresh installs. The lock is what keeps
    /// that from being a data race.
    private static let lock = NSLock()
    private static var models: [String: CatalogRates] = [:]
    private static var fetchedAt: Date?

    static func rates(for canonical: String) -> CatalogRates? {
        lock.lock()
        defer { lock.unlock() }
        return models[canonical]
    }

    static var lastFetched: Date? {
        lock.lock()
        defer { lock.unlock() }
        return fetchedAt
    }

    static func install(models newModels: [String: CatalogRates], fetchedAt stamp: Date) {
        lock.lock()
        defer { lock.unlock() }
        models = newModels
        fetchedAt = stamp
    }

    /// Decides what a response means. Pure, so the whole trust boundary is
    /// testable without a network.
    static func interpret(status: Int, data: Data) -> CatalogFetchResult {
        if status == 304 { return .unchanged }
        guard status == 200 else { return .rejected("HTTP \(status)") }
        guard let payload = try? JSONDecoder().decode(CatalogPayload.self, from: data) else {
            return .rejected("malformed JSON")
        }
        guard payload.schemaVersion == supportedSchemaVersion else {
            return .rejected("unsupported schemaVersion \(payload.schemaVersion)")
        }
        guard !payload.models.isEmpty else { return .rejected("empty catalog") }
        return .payload(payload)
    }
}
```

- [ ] **Step 4: Write the race test**

The lock is the whole reason this store exists rather than a bare `static var`,
and nothing above would notice if it vanished — every assertion so far runs on
one thread. A value assertion cannot catch a data race; a sanitizer can.

Create `Tests/PricingCatalogRaceTests.swift`:

```swift
import Foundation

/// Hammers the store from several threads while a writer swaps the whole
/// table. Built with `-sanitize=thread`: if the lock in `PricingCatalog` is
/// removed, TSan reports the race on the backing dictionary and aborts, so
/// this fails loudly rather than flaking.
@main
struct PricingCatalogRaceTests {
    static func rates(_ input: Double) -> [String: CatalogRates] {
        ["m": CatalogRates(
            displayName: "M", inputPerMillion: input, outputPerMillion: input * 2,
            cacheCreationPerMillion: input, cacheReadPerMillion: 0
        )]
    }

    static func main() {
        let deadline = Date().addingTimeInterval(2)
        let group = DispatchGroup()

        DispatchQueue.global().async(group: group) {
            var flip = false
            while Date() < deadline {
                PricingCatalog.install(models: rates(flip ? 1 : 9), fetchedAt: Date())
                flip.toggle()
            }
        }
        for _ in 0..<4 {
            DispatchQueue.global().async(group: group) {
                while Date() < deadline {
                    _ = PricingCatalog.rates(for: "m")
                    _ = PricingCatalog.lastFetched
                }
            }
        }

        group.wait()
        print("PASS concurrent install/read is race-free")
        exit(0)
    }
}
```

Add the target to `scripts/run-tests.sh`:

```bash
swiftc \
  -parse-as-library \
  -sanitize=thread \
  -o "$OUT_DIR/pricing-catalog-race-tests" \
  Sources/Cost/PricingCatalog.swift \
  Tests/PricingCatalogRaceTests.swift

"$OUT_DIR/pricing-catalog-race-tests"
```

- [ ] **Step 5: Run the tests and prove the race test is load-bearing**

Run: `./scripts/run-tests.sh`

Expected: all existing targets still pass, `pricing-catalog-tests` prints only
PASS lines, and `pricing-catalog-race-tests` prints its single PASS.

Then verify the new test actually guards the lock: temporarily delete the four
`lock.lock()` / `defer { lock.unlock() }` pairs in `PricingCatalog.swift`,
re-run, and confirm TSan reports a data race and the run exits non-zero.
Restore the lock and confirm green again. Report both outputs.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cost/PricingCatalog.swift Tests/PricingCatalogTests.swift Tests/PricingCatalogRaceTests.swift scripts/run-tests.sh
git commit -m "feat(cost): add remote pricing catalog store and payload validation"
```

---

### Task 2: Disk cache and the network refresh

**Files:**
- Modify: `Sources/Cost/PricingCatalog.swift`
- Modify: `Tests/PricingCatalogTests.swift`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces:
  - `struct CachedCatalog: Codable` — `payload: CatalogPayload`, `etag: String?`, `fetchedAt: Date`
  - `PricingCatalog.cacheURL() -> URL?`
  - `PricingCatalog.loadFromDisk(from: URL?)` — parameter defaults to `cacheURL()`
  - `PricingCatalog.persist(_:etag:at:to:)` — parameter defaults to `cacheURL()`
  - `PricingCatalog.refreshIfNeeded(now:fetch:) async`
  - `PricingCatalog.startAutoRefresh()` (`@MainActor`)

- [ ] **Step 1: Write the failing test**

Insert into `Tests/PricingCatalogTests.swift`, immediately before the `exit(...)` line:

```swift
        // Runs before anything installs, because `lastFetched` is nil only on
        // a fresh process — and that is the branch a new install takes. A
        // guard that bailed out when nothing had ever been fetched would mean
        // the app never fetches a catalog at all, and every other assertion
        // in this file would still pass. The transport throws, so the store
        // is left exactly as it was.
        var firstRunRequests = 0
        await PricingCatalog.refreshIfNeeded(now: Date(timeIntervalSince1970: 1_000_000)) { _ in
            firstRunRequests += 1
            throw URLError(.notConnectedToInternet)
        }
        expect(firstRunRequests == 1, "a never-fetched catalog refreshes on first run")

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
            now: base, fetch: transport(200, json(valid), "\"abc\""))
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "200 installs the payload")
        expect(PricingCatalog.lastFetched == base, "200 records the fetch time")

        // Within 24h the refresh is a no-op — no request at all.
        let before = seenHeaders.count
        await PricingCatalog.refreshIfNeeded(
            now: base.addingTimeInterval(3_600), fetch: transport(200, Data(), nil))
        expect(seenHeaders.count == before, "refresh inside 24h makes no request")

        // Past 24h it fetches again, now carrying the stored ETag.
        let later = base.addingTimeInterval(25 * 3_600)
        await PricingCatalog.refreshIfNeeded(now: later, fetch: transport(304, Data(), nil))
        expect(seenHeaders.last == "\"abc\"", "stored ETag is sent as If-None-Match")
        expect(PricingCatalog.lastFetched == later, "304 advances the fetch time")
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "304 preserves the payload")

        // A garbage response must not disturb what is already installed.
        let later2 = later.addingTimeInterval(25 * 3_600)
        await PricingCatalog.refreshIfNeeded(now: later2, fetch: transport(200, json("{nope"), nil))
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "malformed payload leaves the catalog intact")
        expect(PricingCatalog.lastFetched == later, "rejected payload does not advance the clock")

        // A transport that throws is equally harmless.
        await PricingCatalog.refreshIfNeeded(now: later2, fetch: { _ in
            throw URLError(.notConnectedToInternet)
        })
        expect(PricingCatalog.rates(for: "claude-opus-4-8")?.inputPerMillion == 5,
               "network failure leaves the catalog intact")

        // Disk cache: the middle tier of the fallback ladder. Round-trips
        // through a temp file so the user's real cache is never touched.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codexisland-catalog-test.json")
        try? FileManager.default.removeItem(at: tmp)

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
        await PricingCatalog.refreshIfNeeded(now: base.addingTimeInterval(60 * 86_400)) { req in
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

        // Restore a good file for the assertions that follow.
        PricingCatalog.persist(diskPayload, etag: "\"disk\"", at: base, to: tmp)

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
```

Change the harness signature so it can await — replace `static func main() {` with:

```swift
    static func main() async {
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./scripts/run-tests.sh`

Expected: FAIL at compilation — `type 'PricingCatalog' has no member 'refreshIfNeeded'`.

- [ ] **Step 3: Write the disk cache and refresh**

Append to `Sources/Cost/PricingCatalog.swift`, inside the `PricingCatalog` enum:

```swift
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    private static var etag: String?

    private static var storedETag: String? {
        get { lock.lock(); defer { lock.unlock() }; return etag }
        set { lock.lock(); defer { lock.unlock() }; etag = newValue }
    }

    /// Records that the source was reached and confirmed unchanged, without
    /// touching the price table.
    static func markVerified(at stamp: Date) {
        lock.lock()
        defer { lock.unlock() }
        fetchedAt = stamp
    }

    struct CachedCatalog: Codable {
        let payload: CatalogPayload
        let etag: String?
        let fetchedAt: Date
    }

    /// `Caches` is purgeable by macOS. Losing this file costs one refetch and
    /// drops to the embedded seed in the meantime, which is the intended
    /// behavior — mirrors `LogParseCache.cacheURL`.
    static func cacheURL() -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("dev.codexisland.CodexIsland", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("model-prices.json")
    }

    /// The URL parameter exists so tests can round-trip through a temp file
    /// instead of the user's real cache.
    static func loadFromDisk(from url: URL? = cacheURL()) {
        guard let url,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedCatalog.self, from: data),
              cached.payload.schemaVersion == supportedSchemaVersion,
              !cached.payload.models.isEmpty
        else { return }
        storedETag = cached.etag
        install(models: cached.payload.models, fetchedAt: cached.fetchedAt)
    }

    static func persist(
        _ payload: CatalogPayload, etag newETag: String?, at stamp: Date,
        to url: URL? = cacheURL()
    ) {
        storedETag = newETag
        guard let url,
              let data = try? JSONEncoder().encode(
                CachedCatalog(payload: payload, etag: newETag, fetchedAt: stamp))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func refreshIfNeeded(
        now: Date = Date(),
        fetch: (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) async {
        if let last = lastFetched, now.timeIntervalSince(last) < refreshInterval { return }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        if let tag = storedETag { request.setValue(tag, forHTTPHeaderField: "If-None-Match") }

        guard let (data, response) = try? await fetch(request),
              let http = response as? HTTPURLResponse
        else { return }

        switch interpret(status: http.statusCode, data: data) {
        case .payload(let payload):
            install(models: payload.models, fetchedAt: now)
            persist(payload, etag: http.value(forHTTPHeaderField: "ETag"), at: now)
        case .unchanged:
            markVerified(at: now)
        case .rejected:
            // Deliberately silent and deliberately inert: staleness already
            // surfaces in Settings, and the previous catalog stays correct.
            break
        }
    }

    @MainActor
    private static var refreshTimer: Timer?

    /// Ticks every 6h against a 24h staleness threshold, so a laptop that
    /// slept through its window catches up at the next wake rather than
    /// waiting another full day.
    @MainActor
    static func startAutoRefresh() {
        Task { await refreshIfNeeded() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in
            Task { await refreshIfNeeded() }
        }
    }
```

- [ ] **Step 4: Extend the race harness to the accessors this task added**

`Tests/PricingCatalogRaceTests.swift` was written in Task 1 and its threads
touch only Task 1's accessors. `storedETag` and `markVerified(at:)` are new
shared state, and stripping their locks leaves the sanitizer silent — the
regression net stops at the task boundary unless it is widened here.

**One accessor per thread.** This is the load-bearing detail, not a style
choice. If a single thread calls `install`, `markVerified`, and `persist` in
sequence, the locks in the calls on either side of an unlocked one establish
happens-before edges that cover it, and the sanitizer stays silent even though
the write is genuinely unsynchronized. Give each accessor a thread whose only
synchronization is its own lock, so removing that lock leaves the thread with
no edges at all.

Replace the single writer closure with three:

```swift
        DispatchQueue.global().async(group: group) {
            var flip = false
            while Date() < deadline {
                PricingCatalog.install(models: rates(flip ? 1 : 9), fetchedAt: Date())
                flip.toggle()
            }
        }
        DispatchQueue.global().async(group: group) {
            while Date() < deadline {
                PricingCatalog.markVerified(at: Date())
            }
        }
        DispatchQueue.global().async(group: group) {
            var flip = false
            while Date() < deadline {
                // to: nil writes no file — this exists only to touch the ETag,
                // which nothing public reads, so the race it must expose is
                // write-against-write between this thread and the next.
                PricingCatalog.persist(
                    CatalogPayload(schemaVersion: 1, generatedAt: "x", models: rates(1)),
                    etag: flip ? "\"a\"" : "\"b\"", at: Date(), to: nil)
                flip.toggle()
            }
        }
        DispatchQueue.global().async(group: group) {
            while Date() < deadline {
                PricingCatalog.persist(
                    CatalogPayload(schemaVersion: 1, generatedAt: "y", models: rates(2)),
                    etag: "\"c\"", at: Date(), to: nil)
            }
        }
```

- [ ] **Step 5: Run the tests, and prove the new coverage is load-bearing**

Run: `./scripts/run-tests.sh`

Expected: all targets pass.

Then mutate each new lock individually and confirm the sanitizer now catches
what it previously missed. Remove the lock from `storedETag`'s getter and
setter, re-run, confirm TSan reports a race and the run exits non-zero.
Restore. Repeat for `markVerified(at:)`. Report both, and report the same for
the three assertions added in Step 1 — delete `storedETag = cached.etag` from
`loadFromDisk`, delete the `etag:` argument from `persist`'s encoded envelope,
and rewrite the 24h guard so a nil `lastFetched` returns early. Each must fail
a named assertion. If any mutation leaves the suite green, say so plainly —
that means the assertion does not pin what it claims.

- [ ] **Step 6: Commit**

```bash
git add Sources/Cost/PricingCatalog.swift Tests/PricingCatalogTests.swift Tests/PricingCatalogRaceTests.swift
git commit -m "feat(cost): add disk cache and daily conditional refresh for pricing catalog"
```

---

### Task 3: Demote the embedded table to a seed

**Files:**
- Modify: `Sources/Cost/Pricing.swift`
- Create: `Tests/PricingTests.swift`
- Modify: `scripts/run-tests.sh`

**Interfaces:**
- Consumes: `PricingCatalog.rates(for:)`, `PricingCatalog.lastFetched` from Tasks 1–2.
- Produces:
  - `Pricing.seedSnapshotDate` (renamed from `snapshotDate`)
  - `Pricing.daysSincePricingRefresh(now:) -> Int` (replaces `daysSinceSnapshot`)
  - `Pricing.cost(for:)`, `isKnown(_:)`, `prettyModelName(_:)` — same signatures, catalog-first behavior

- [ ] **Step 1: Write the failing test**

Create `Tests/PricingTests.swift`:

```swift
import Foundation

/// Locks down lookup precedence: the remote catalog decides prices when it
/// has an entry, the embedded seed covers everything else, and neither can
/// be knocked out by the other.
@main
struct PricingTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func ev(_ model: String, input: Int = 1_000_000) -> TokenEvent {
        TokenEvent(
            provider: .claude, timestamp: now, model: model,
            inputTokens: input, outputTokens: 0,
            cacheCreationTokens: 0, cacheReadTokens: 0, project: nil
        )
    }

    static func main() {
        // Runs first, before any install: with no successful fetch the
        // freshness number falls back to the seed's build date.
        expect(Pricing.daysSincePricingRefresh(now: now) > 0,
               "seed date drives freshness before any fetch")

        // Seed-only behavior still works untouched.
        expect(Pricing.cost(for: ev("claude-opus-4-8")) == 5, "seed prices opus at $5/M input")
        expect(Pricing.isKnown("claude-sonnet-4-5"), "seed model is known")
        expect(!Pricing.isKnown("totally-made-up"), "unknown model stays unknown")

        // Install a catalog that disagrees with the seed on one model and
        // adds one the seed has never heard of.
        PricingCatalog.install(
            models: [
                "claude-opus-4-8": CatalogRates(
                    displayName: "Opus 4.8", inputPerMillion: 7, outputPerMillion: 25,
                    cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.5),
                "gpt-7-quasar": CatalogRates(
                    displayName: "GPT-7 Quasar", inputPerMillion: 3, outputPerMillion: 12,
                    cacheCreationPerMillion: 3, cacheReadPerMillion: 0.3),
            ],
            fetchedAt: now.addingTimeInterval(-3 * 86_400)
        )

        expect(Pricing.cost(for: ev("claude-opus-4-8")) == 7, "remote rate beats the seed")
        expect(Pricing.cost(for: ev("gpt-7-quasar")) == 3, "remote-only model is priced")
        expect(Pricing.isKnown("gpt-7-quasar"), "remote-only model is known")

        // Seed models absent from the catalog keep working — this is the
        // fallback that stops a partial payload from zeroing out costs.
        expect(Pricing.cost(for: ev("claude-sonnet-4-5")) == 3, "seed still covers what remote omits")
        expect(Pricing.isKnown("gpt-5-mini"), "seed-only model stays known")

        // Date-pinned ids canonicalize before lookup, remote included.
        expect(Pricing.cost(for: ev("claude-opus-4-8-20260101")) == 7,
               "date-pinned id resolves to the remote entry")

        // Display names: remote wins, algorithm fills the gap.
        expect(Pricing.prettyModelName("gpt-7-quasar") == "GPT-7 Quasar",
               "remote displayName is used")
        expect(Pricing.prettyModelName("claude-sonnet-4-5") == "Sonnet 4.5",
               "algorithm covers models the catalog omits")

        // Freshness now tracks the successful fetch, not the seed date.
        expect(Pricing.daysSincePricingRefresh(now: now) == 3,
               "freshness counts days since last successful fetch")

        exit(failures == 0 ? 0 : 1)
    }
}
```

- [ ] **Step 2: Add the test target and run it to verify it fails**

Append to `scripts/run-tests.sh`:

```bash
swiftc \
  -parse-as-library \
  -o "$OUT_DIR/pricing-tests" \
  Sources/Cost/TokenEvent.swift \
  Sources/Cost/PricingCatalog.swift \
  Sources/Cost/Pricing.swift \
  Tests/PricingTests.swift

"$OUT_DIR/pricing-tests"
```

Run: `./scripts/run-tests.sh`

Expected: FAIL at compilation — `type 'Pricing' has no member 'daysSincePricingRefresh'`.

- [ ] **Step 3: Rename the table and snapshot constant**

In `Sources/Cost/Pricing.swift`:

- Change `static let snapshotDate = "2026-07-10"` to `static let seedSnapshotDate = "2026-07-10"`.
- Change `private static let table: [String: Rates] = [` to `private static let seedTable: [String: Rates] = [`. Leave every entry in it exactly as-is.
- Replace the doc comment above `enum Pricing` with:

```swift
/// Model prices in USD per million tokens.
///
/// The live source is the published catalog (see `PricingCatalog`); the
/// table below is the build-time seed used until the first successful fetch,
/// and as the permanent fallback for anything the catalog omits. Unknown
/// models silently price to $0 — same behavior as ccusage when LiteLLM has
/// no entry.
///
/// To refresh the seed: re-fetch the four rates per model from
/// `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`
/// and bump `seedSnapshotDate`. This is housekeeping, not a release
/// requirement — the catalog covers new models without an app update.
```

- [ ] **Step 4: Route lookups through the catalog**

Replace the bodies of `cost(for:)` and `isKnown(_:)`, and add the resolver. In `Sources/Cost/Pricing.swift`:

```swift
    /// Remote catalog first, embedded seed second. The seed is what keeps a
    /// catalog that omits a model from silently pricing it at $0.
    private static func resolvedRates(for canonical: String) -> Rates? {
        if let remote = PricingCatalog.rates(for: canonical) {
            return Rates(
                inputPerMillion: remote.inputPerMillion,
                outputPerMillion: remote.outputPerMillion,
                cacheCreationPerMillion: remote.cacheCreationPerMillion,
                cacheReadPerMillion: remote.cacheReadPerMillion
            )
        }
        return seedTable[canonical]
    }

    static func cost(for event: TokenEvent) -> Double {
        guard let rates = resolvedRates(for: canonicalModel(event.model)) else { return 0 }

        let input = Double(event.inputTokens) / 1_000_000 * rates.inputPerMillion
        let output = Double(event.outputTokens) / 1_000_000 * rates.outputPerMillion
        let cacheCreate = Double(event.cacheCreationTokens) / 1_000_000 * rates.cacheCreationPerMillion
        let cacheRead = Double(event.cacheReadTokens) / 1_000_000 * rates.cacheReadPerMillion

        return input + output + cacheCreate + cacheRead
    }

    static func isKnown(_ rawModel: String) -> Bool {
        resolvedRates(for: canonicalModel(rawModel)) != nil
    }
```

- [ ] **Step 5: Replace the freshness computation**

Delete the whole `static var daysSinceSnapshot: Int { ... }` block and put this in its place:

```swift
    private static let snapshotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Days since the app last reached the catalog, falling back to the age
    /// of the embedded seed when no fetch has ever succeeded.
    ///
    /// Deliberately not the catalog's own `generatedAt`: the sync bot commits
    /// only when prices change, so a long-stable table would read as months
    /// stale while the app was in fact checking daily and finding nothing new.
    /// "How long since I reached the source" is what actually predicts whether
    /// these numbers are wrong.
    static func daysSincePricingRefresh(now: Date = Date()) -> Int {
        let origin = PricingCatalog.lastFetched
            ?? snapshotFormatter.date(from: seedSnapshotDate)
        guard let origin else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") { calendar.timeZone = utc }
        return max(0, calendar.dateComponents([.day], from: origin, to: now).day ?? 0)
    }
```

- [ ] **Step 6: Let the catalog supply display names**

Insert at the very top of `prettyModelName(_:)`, before the `claude-` branch:

```swift
        if let name = PricingCatalog.rates(for: canonical)?.displayName, !name.isEmpty {
            return name
        }
```

- [ ] **Step 7: Add `PricingCatalog.swift` to the two existing targets that compile `Pricing.swift`**

In `scripts/run-tests.sh`, add the line `  Sources/Cost/PricingCatalog.swift \` immediately above `  Sources/Cost/Pricing.swift \` in **both** the `stat-card-summary-tests` and `stat-card-render-tests` invocations.

- [ ] **Step 8: Run the full suite**

Run: `./scripts/run-tests.sh`

Expected: every target passes, including the pre-existing `stat-card-summary-tests` and `stat-card-render-tests` — they exercise `Pricing.cost(for:)` with no catalog installed, which proves the seed fallback still works.

- [ ] **Step 9: Commit**

```bash
git add Sources/Cost/Pricing.swift Tests/PricingTests.swift scripts/run-tests.sh
git commit -m "feat(cost): resolve prices from remote catalog before embedded seed"
```

---

### Task 4: Wire into launch, update Settings, disclose in README

**Files:**
- Modify: `Sources/App.swift:21-51`
- Modify: `Sources/Views/SettingsView.swift:607`
- Modify: `README.md:273-286`

**Interfaces:**
- Consumes: `PricingCatalog.loadFromDisk()`, `PricingCatalog.startAutoRefresh()`, `Pricing.daysSincePricingRefresh(now:)`.
- Produces: nothing downstream.

- [ ] **Step 1: Load the cache before anything summarizes**

In `Sources/App.swift`, insert as the **first** statement of `applicationDidFinishLaunching`, above `NSApp.setActivationPolicy(.accessory)`:

```swift
        // Before any window or store exists: the first cost scan must price
        // against the cached catalog, not fall back to the seed and then
        // silently change its numbers a moment later.
        PricingCatalog.loadFromDisk()
```

- [ ] **Step 2: Start the refresh alongside the other stores**

In the same function, add immediately after `CostStore.shared.startAutoRefresh()`:

```swift
        PricingCatalog.startAutoRefresh()
```

- [ ] **Step 3: Point the Settings subtitle at the new freshness number**

In `Sources/Views/SettingsView.swift:607`, change:

```swift
        let days = Pricing.daysSinceSnapshot
```

to:

```swift
        let days = Pricing.daysSincePricingRefresh()
```

Leave `pricingFreshnessThreshold` and all three `L10n.tr` strings exactly as they are — the wording still reads correctly, and no localization keys change.

- [ ] **Step 4: Build the app**

Run: `./build.sh`

Expected: builds clean with no warnings about `PricingCatalog`. `build.sh` globs `Sources/**/*.swift`, so the new file needs no registration.

- [ ] **Step 5: Verify against a real fetch**

```bash
curl -sS https://ericjypark.github.io/codex-island-model-catalog/v1/models.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['schemaVersion'], len(d['models']))"
```

Expected: `1` and a model count. If the companion service plan has not shipped yet, this 404s — that is fine, and the app correctly stays on its seed. Skip to Step 6 and revisit after the service is live.

Then launch the built app, open Settings, and confirm the Cost row reads `last scan … ` with no `pricing data Nd old` suffix (a fresh fetch means 0 days).

- [ ] **Step 6: Disclose the new network destination in the README**

The Privacy section currently implies the app talks only to `chatgpt.com` and `api.anthropic.com`. In `README.md`, inside the `## Privacy` list, add after the line `- No credentials are stored by CodexIsland.`:

```markdown
- Model prices are fetched once a day from a public GitHub-hosted catalog
  ([codex-island-model-catalog](https://github.com/ericjypark/codex-island-model-catalog)).
  The request carries no identifier, no token, and no usage data — it is a
  plain GET for a static JSON file, and the app works from a local cache
  when it fails.
```

Leave `- No app telemetry.` and `- No app analytics.` untouched. Both remain true.

- [ ] **Step 7: Run the full suite one more time and commit**

```bash
./scripts/run-tests.sh
git add Sources/App.swift Sources/Views/SettingsView.swift README.md
git commit -m "feat(cost): load pricing catalog at launch and disclose the fetch"
```

---

## Done when

- `./scripts/run-tests.sh` passes every target, including the two pre-existing stat-card targets.
- `./build.sh` succeeds and the app launches.
- With the endpoint live: Settings shows no staleness suffix, and per-model rows use catalog display names.
- With the network unplugged and the cache deleted (`rm ~/Library/Caches/dev.codexisland.CodexIsland/model-prices.json`): the app still shows non-zero costs, priced from the seed.
- `grep -n "No app telemetry" README.md` still matches.
