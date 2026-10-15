import Foundation

/// Locks down catalog-over-seed lookup precedence: the remote catalog decides prices when it has
/// an entry, the embedded seed covers everything else, and neither can knock
/// out the other.
@main
struct PricingPrecedenceTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func ev(_ model: String, input: Int = 1_000_000) -> TokenEvent {
        TokenEvent(
            provider: .claude, timestamp: now, model: model,
            inputTokens: input, outputTokens: 0,
            cacheCreationTokens: 0, cacheReadTokens: 0
        )
    }

    static func main() {
        // Seed-only behavior, unchanged from before the catalog existed.
        expect(Pricing.cost(for: ev("claude-opus-4-8")) == 5, "seed prices opus at $5/M input")
        expect(Pricing.isKnown("claude-sonnet-4-5"), "seed model is known")
        expect(!Pricing.isKnown("totally-made-up"), "unknown model stays unknown")

        // A catalog that disagrees with the seed on one model and adds one the
        // seed has never heard of.
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

        // The fallback that stops a partial catalog from zeroing out costs.
        expect(Pricing.cost(for: ev("claude-sonnet-4-5")) == 3, "seed still covers what remote omits")
        expect(Pricing.isKnown("gpt-5-mini"), "seed-only model stays known")

        // Date-pinned ids canonicalize before lookup, remote included.
        expect(Pricing.cost(for: ev("claude-opus-4-8-20260101")) == 7,
               "date-pinned id resolves to the remote entry")

        // Display names: remote wins, the algorithm fills the gap.
        expect(Pricing.prettyModelName("gpt-7-quasar") == "GPT-7 Quasar",
               "remote displayName is used")
        expect(Pricing.prettyModelName("claude-sonnet-4-5") == "Sonnet 4.5",
               "algorithm covers models the catalog omits")

        exit(failures == 0 ? 0 : 1)
    }
}
