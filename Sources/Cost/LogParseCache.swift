import Foundation

/// Shared scaffolding for the per-provider JSONL log readers (Claude, Codex).
/// Owns the file walk, the (path, mtime, size) cache, and the chunked
/// streaming reader so both providers behave identically on large rollout
/// files. Each provider supplies only its `Event` Codable shape and a
/// `parseFile` closure that consumes lines one at a time.
enum LogParseCache {
    struct FileEntry {
        let url: URL
        let mtime: Date
        let size: Int64
    }

    /// Walks `root` and returns every `*.jsonl` modified at or after `cutoff`.
    /// Caller can additionally filter by filename via `filter`.
    static func jsonlFiles(
        under root: URL,
        modifiedAfter cutoff: Date,
        filter: (URL) -> Bool = { _ in true }
    ) -> [FileEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var hits: [FileEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", filter(url) else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true,
                  let mtime = values?.contentModificationDate,
                  let size = values?.fileSize else { continue }
            if mtime < cutoff { continue }
            hits.append(FileEntry(url: url, mtime: mtime, size: Int64(size)))
        }
        return hits
    }

    /// Stream `url` in 64 KB chunks and invoke `onLine` once per newline-
    /// terminated line, plus once for any trailing line lacking a newline.
    /// Session JSONLs can reach hundreds of MB and we may walk months of
    /// them, so loading entire files via `Data(contentsOf:)` blows up peak
    /// memory. Newlines are found with `memchr` over only the bytes added
    /// since the last search: Codex rollout files write 20+ MB single lines,
    /// and the old `Data.firstIndex` path rescanned the whole growing buffer
    /// on every chunk, turning one such line into O(N²). Buffer trim still
    /// happens once per chunk, not once per line.
    static func streamLines(at url: URL, onLine: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        var scanned = 0
        let chunkSize = 64 * 1024

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            var cursor = 0
            var searchFrom = scanned
            while let nl = firstNewline(in: buffer, from: searchFrom) {
                if nl > cursor { onLine(buffer[cursor..<nl]) }
                cursor = nl + 1
                searchFrom = nl + 1
            }
            scanned = buffer.count - cursor
            if cursor > 0 { buffer.removeSubrange(0..<cursor) }
        }
        if !buffer.isEmpty { onLine(buffer) }
    }

    /// Offset of the first 0x0A at or after `start`, or nil. `memchr` is
    /// vectorized and skips the per-byte bounds-checked `Data` subscript that
    /// dominated the sample profile on large session logs.
    private static func firstNewline(in data: Data, from start: Int) -> Int? {
        guard start < data.count else { return nil }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            guard let hit = memchr(base + start, 0x0A, data.count - start) else { return nil }
            return UnsafeRawPointer(hit) - base
        }
    }

    /// Per-file cache entry. Generic over the provider's `Event` Codable shape.
    struct CachedFile<Event: Codable>: Codable {
        let mtime: Date
        let size: Int64
        let events: [Event]

        /// Tolerate sub-millisecond drift through JSON's Double round-trip;
        /// any real edit moves mtime by far more than that or grows size.
        func matches(mtime other: Date, size otherSize: Int64) -> Bool {
            guard size == otherSize else { return false }
            return abs(mtime.timeIntervalSinceReferenceDate - other.timeIntervalSinceReferenceDate) < 0.001
        }
    }

    struct ParseCache<Event: Codable>: Codable {
        var version: Int
        var files: [String: CachedFile<Event>]
    }

    private static func cacheURL(filename: String) -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("dev.codexisland.CodexIsland", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    static func loadCache<Event: Codable>(
        filename: String,
        version: Int,
        eventType: Event.Type
    ) -> ParseCache<Event> {
        guard let url = cacheURL(filename: filename),
              let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ParseCache<Event>.self, from: data),
              cache.version == version
        else { return ParseCache<Event>(version: version, files: [:]) }
        return cache
    }

    static func saveCache<Event: Codable>(_ cache: ParseCache<Event>, filename: String) {
        guard let url = cacheURL(filename: filename),
              let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Walk `roots`, parse uncached files, and return every cached event
    /// from files modified on or after `cutoff`. Per-event filtering and
    /// dedup are the caller's responsibility — this layer only handles
    /// the cache hit/miss + stale-entry prune.
    static func walk<Event: Codable>(
        roots: [URL],
        cutoff: Date,
        cacheFilename: String,
        cacheVersion: Int,
        fileFilter: (URL) -> Bool = { _ in true },
        parse: (URL) -> [Event],
        emit: (Event) -> Void
    ) {
        var cache = loadCache(filename: cacheFilename, version: cacheVersion, eventType: Event.self)
        var visited = Set<String>()
        var cacheChanged = false

        for root in roots {
            for entry in jsonlFiles(under: root, modifiedAfter: cutoff, filter: fileFilter) {
                let path = entry.url.path
                visited.insert(path)

                let events: [Event]
                if let hit = cache.files[path], hit.matches(mtime: entry.mtime, size: entry.size) {
                    events = hit.events
                } else {
                    events = parse(entry.url)
                    cache.files[path] = CachedFile(mtime: entry.mtime, size: entry.size, events: events)
                    cacheChanged = true
                }
                for ev in events { emit(ev) }
            }
        }

        // Drop cache entries for files that disappeared or rolled out of the
        // cutoff — otherwise the cache grows unbounded over months.
        let preCount = cache.files.count
        cache.files = cache.files.filter { visited.contains($0.key) }
        if cache.files.count != preCount { cacheChanged = true }

        if cacheChanged { saveCache(cache, filename: cacheFilename) }
    }
}
