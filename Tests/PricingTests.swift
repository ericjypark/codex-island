import Foundation

/// Locks down the embedded price snapshot: every model Claude Code and Codex
/// CLI actually emit is priced, the four rates are applied to the right token
/// buckets, and date-pinned ids fold onto their base entry.
@main
struct PricingTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS \(label)") } else { print("FAIL \(label)"); failures += 1 }
    }

    static func ev(
        _ model: String,
        input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0
    ) -> TokenEvent {
        TokenEvent(
            provider: .claude, timestamp: Date(), model: model,
            inputTokens: input, outputTokens: output,
            cacheCreationTokens: cacheCreation, cacheReadTokens: cacheRead
        )
    }

    static func main() {
        // Every model id observed in real session logs must price. A miss here
        // is what surfaces as the cost screen's "⚠ N unpriced" badge.
        for model in [
            "claude-fable-5", "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7",
            "claude-sonnet-5", "claude-haiku-4-5-20251001",
            "gpt-5.6", "gpt-5.3-codex",
        ] {
            expect(Pricing.isKnown(model), "\(model) is priced")
        }

        // Opus 5 sits in the re-tiered Opus band: $5 / $25 / $6.25 / $0.50.
        // One million of each bucket makes the per-million rates readable.
        let opus5 = Pricing.cost(for: ev(
            "claude-opus-5",
            input: 1_000_000, output: 1_000_000,
            cacheCreation: 1_000_000, cacheRead: 1_000_000
        ))
        expect(abs(opus5 - 36.75) < 0.0001, "opus-5 rates land in the right buckets")

        // Same band as 4-8 — a divergence means one of the two was edited alone.
        let opus48 = Pricing.cost(for: ev(
            "claude-opus-4-8",
            input: 1_000_000, output: 1_000_000,
            cacheCreation: 1_000_000, cacheRead: 1_000_000
        ))
        expect(abs(opus5 - opus48) < 0.0001, "opus-5 matches the opus-4-8 tier")

        // Not the Fable tier — guards against pasting the wrong neighbor's rates.
        expect(
            Pricing.cost(for: ev("claude-fable-5", input: 1_000_000)) == 10,
            "fable-5 stays at its own $10 input rate"
        )

        // Date-pinned ids fold onto the base entry rather than needing a row.
        expect(
            Pricing.canonicalModelName("claude-opus-5-20260715") == "claude-opus-5",
            "date suffix stripped from opus-5"
        )
        expect(
            Pricing.isKnown("claude-opus-5-20260715"),
            "date-pinned opus-5 prices via its base entry"
        )
        // The "-5" tail is not a date suffix — stripping it would break lookup.
        expect(
            Pricing.canonicalModelName("claude-opus-5") == "claude-opus-5",
            "bare opus-5 is left intact"
        )

        expect(Pricing.prettyModelName("claude-opus-5") == "Opus 5", "opus-5 renders as Opus 5")

        // ccusage parity: an id we have no row for costs $0 rather than crashing.
        expect(
            Pricing.cost(for: ev("claude-opus-9", input: 1_000_000)) == 0,
            "unknown model prices to zero"
        )

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
