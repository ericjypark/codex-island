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

    /// A 304 means the source was reached and the payload is still current, so
    /// the timestamp has to reach disk too — `markVerified` only moves the
    /// in-memory copy. Without this, every launch restores the older stamp and
    /// the 24h refresh window is computed from the wrong instant.
    static func touchCache(at stamp: Date, to url: URL? = cacheURL()) {
        guard let url,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedCatalog.self, from: data)
        else { return }
        persist(cached.payload, etag: cached.etag, at: stamp, to: url)
    }

    static func refreshIfNeeded(
        now: Date = Date(),
        cache: URL? = cacheURL(),
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
            persist(payload, etag: http.value(forHTTPHeaderField: "ETag"), at: now, to: cache)
        case .unchanged:
            markVerified(at: now)
            touchCache(at: now, to: cache)
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
}
