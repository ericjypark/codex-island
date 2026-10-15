import Foundation

/// Hammers the store from several threads, one accessor per thread. Built
/// with `-sanitize=thread`: removing a lock leaves that thread with no
/// happens-before edges, TSan reports the race and aborts, so this fails
/// loudly rather than flaking.
///
/// One accessor per writer thread is load-bearing, not style. With a single
/// thread calling several accessors in sequence, the locks on either side of
/// an unlocked one cover it and the sanitizer stays silent.
///
/// **What this harness does and does not protect.** Verified by removing each
/// lock in turn: `install`, `rates(for:)` and `storedETag` all abort with a
/// TSan report. `markVerified(at:)` and `lastFetched` do not — removing their
/// locks is not detected at all.
///
/// The boundary is the field's storage kind, not this harness's shape. On this
/// toolchain TSan reports races on heap-backed refcounted storage — `models`
/// (Dictionary) and `etag` (String) — and not on inline POD storage. A
/// standalone probe racing a `static var Date?` with no lock anywhere in the
/// program reports nothing; the same probe on `[String: Double]` or `String?`
/// aborts. Both uncovered accessors are exactly the two whose only shared
/// state is `fetchedAt: Date?`.
///
/// So this is not a gap a further redesign closes — it is undetectable by
/// construction for that field type. The consequence for anyone extending
/// `PricingCatalog`: a new lock-guarded `Int`, `Date`, or other POD field will
/// NOT be covered here, and its lock has to be argued for by reading rather
/// than proven by this test.
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
        for _ in 0..<2 {
            DispatchQueue.global().async(group: group) {
                while Date() < deadline {
                    _ = PricingCatalog.rates(for: "m")
                }
            }
        }
        for _ in 0..<2 {
            DispatchQueue.global().async(group: group) {
                while Date() < deadline {
                    _ = PricingCatalog.lastFetched
                }
            }
        }

        group.wait()
        print("PASS concurrent install/read is race-free")
        exit(0)
    }
}
