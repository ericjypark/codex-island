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
    /// Session JSONLs can reach 50+ MB and we may walk months of them, so
    /// loading entire files via `Data(contentsOf:)` blows up peak memory.
    ///
    /// Newline scanning happens on each freshly-read chunk (always ≤64KB), and
    /// only the in-progress partial line is carried forward in `pending`. The
    /// previous implementation appended every chunk to one growing buffer and
    /// re-scanned it from the cursor each time, which is O(N²) for a single
    /// long line — a Codex session that embeds base64 images produces lines
    /// up to ~50MB, and a 10GB home of them pegged a core for minutes. Here a
    /// long line only ever costs the per-chunk scan plus appends to `pending`.
    ///
    /// `maxLineBytes` caps a single line: once `pending` exceeds it, the line
    /// is abandoned (never buffered further, never delivered) and bytes are
    /// dropped until the next newline. Defaults to no cap so existing callers
    /// (Claude) are byte-for-byte unchanged; the Codex reader opts in to skip
    /// the image/payload blobs it never needs to parse.
    static func streamLines(at url: URL, maxLineBytes: Int = .max, onLine: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let chunkSize = 64 * 1024
        var pending = Data()          // partial line carried across chunk reads
        var skippingLongLine = false  // discarding an over-cap line until its '\n'

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            var lineStart = chunk.startIndex
            while let nl = chunk[lineStart..<chunk.endIndex].firstIndex(of: 0x0A) {
                if skippingLongLine {
                    // Reached the end of the abandoned line; resume normally.
                    skippingLongLine = false
                    pending.removeAll(keepingCapacity: true)
                } else if pending.isEmpty {
                    if nl > lineStart { onLine(chunk[lineStart..<nl]) }
                } else {
                    pending.append(chunk[lineStart..<nl])
                    onLine(pending)
                    pending.removeAll(keepingCapacity: true)
                }
                lineStart = chunk.index(after: nl)
            }

            // Bytes after the last newline form (the start of) the next line.
            if lineStart < chunk.endIndex, !skippingLongLine {
                pending.append(chunk[lineStart..<chunk.endIndex])
                if pending.count > maxLineBytes {
                    pending.removeAll(keepingCapacity: true)
                    skippingLongLine = true
                }
            }
        }
        if !skippingLongLine, !pending.isEmpty { onLine(pending) }
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
