import Foundation

/// Model prices in USD per million tokens.
///
/// The live source is the published catalog (see `PricingCatalog`); the table
/// below is the build-time seed, used until the first successful fetch and as
/// the permanent fallback for anything the catalog omits. Totals cross-check
/// against `npx ccusage` and `npx @ccusage/codex` to within rounding, and
/// unknown models silently price to $0 — same behavior as ccusage when
/// LiteLLM has no entry.
///
/// To refresh the seed: re-fetch the four rates per model from
/// `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`.
/// This is housekeeping, not a release requirement — the catalog covers new
/// models without an app update.
enum Pricing {
    struct Rates {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheCreationPerMillion: Double
        let cacheReadPerMillion: Double
    }

    private static let seedTable: [String: Rates] = [
        // Anthropic — LiteLLM lists Opus 5 and 4-5/4-6/4-7/4-8 at the same
        // rates (cheaper than the original Opus 4 because Anthropic re-tiered
        // the Opus line in 2025). Opus 5's fast mode bills at $10/$50 but
        // Claude Code logs it under the same `claude-opus-5` id with no speed
        // marker in `message.model`, so — like ccusage — we price every row at
        // the standard tier.
        "claude-fable-5": Rates(
            inputPerMillion: 10, outputPerMillion: 50,
            cacheCreationPerMillion: 12.50, cacheReadPerMillion: 1.00
        ),
        "claude-opus-5": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-8": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-7": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-6": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "claude-opus-4-5": Rates(
            inputPerMillion: 5, outputPerMillion: 25,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        // Sonnet 5 rates reflect Anthropic's introductory pricing ($2/$10
        // through 2026-08-31; $3/$15 after) — matches LiteLLM's current entry.
        "claude-sonnet-5": Rates(
            inputPerMillion: 2, outputPerMillion: 10,
            cacheCreationPerMillion: 2.50, cacheReadPerMillion: 0.20
        ),
        "claude-sonnet-4-6": Rates(
            inputPerMillion: 3, outputPerMillion: 15,
            cacheCreationPerMillion: 3.75, cacheReadPerMillion: 0.30
        ),
        "claude-sonnet-4-5": Rates(
            inputPerMillion: 3, outputPerMillion: 15,
            cacheCreationPerMillion: 3.75, cacheReadPerMillion: 0.30
        ),
        "claude-haiku-4-5": Rates(
            inputPerMillion: 1, outputPerMillion: 5,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.10
        ),

        // OpenAI — Codex CLI tags conversations with the chat-completion
        // model name. cache_creation has no separate rate (OpenAI bills
        // cache writes at the standard input rate).
        // Base reasoning models (newest first). Starting with 5.6, OpenAI
        // bills cache writes at 1.25x input (matching Anthropic) instead of
        // the standard input rate.
        "gpt-5.6": Rates(
            inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "gpt-5.6-sol": Rates(
            inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 6.25, cacheReadPerMillion: 0.50
        ),
        "gpt-5.6-terra": Rates(
            inputPerMillion: 2.5, outputPerMillion: 15,
            cacheCreationPerMillion: 3.125, cacheReadPerMillion: 0.25
        ),
        "gpt-5.6-luna": Rates(
            inputPerMillion: 1, outputPerMillion: 6,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.10
        ),
        "gpt-5.5": Rates(
            inputPerMillion: 5, outputPerMillion: 30,
            cacheCreationPerMillion: 5, cacheReadPerMillion: 0.50
        ),
        "gpt-5.4": Rates(
            inputPerMillion: 2.5, outputPerMillion: 15,
            cacheCreationPerMillion: 2.5, cacheReadPerMillion: 0.25
        ),
        "gpt-5.2": Rates(
            inputPerMillion: 1.75, outputPerMillion: 14,
            cacheCreationPerMillion: 1.75, cacheReadPerMillion: 0.175
        ),
        "gpt-5.1": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        "gpt-5": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        // Codex variants (newest first).
        "gpt-5.3-codex": Rates(
            inputPerMillion: 1.75, outputPerMillion: 14,
            cacheCreationPerMillion: 1.75, cacheReadPerMillion: 0.175
        ),
        "gpt-5.2-codex": Rates(
            inputPerMillion: 1.75, outputPerMillion: 14,
            cacheCreationPerMillion: 1.75, cacheReadPerMillion: 0.175
        ),
        "gpt-5.1-codex": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        "gpt-5.1-codex-max": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        "gpt-5.1-codex-mini": Rates(
            inputPerMillion: 0.25, outputPerMillion: 2,
            cacheCreationPerMillion: 0.25, cacheReadPerMillion: 0.025
        ),
        "gpt-5-codex": Rates(
            inputPerMillion: 1.25, outputPerMillion: 10,
            cacheCreationPerMillion: 1.25, cacheReadPerMillion: 0.125
        ),
        // Mini / nano tiers.
        "gpt-5.4-mini": Rates(
            inputPerMillion: 0.75, outputPerMillion: 4.5,
            cacheCreationPerMillion: 0.75, cacheReadPerMillion: 0.075
        ),
        "gpt-5.4-nano": Rates(
            inputPerMillion: 0.2, outputPerMillion: 1.25,
            cacheCreationPerMillion: 0.2, cacheReadPerMillion: 0.02
        ),
        "gpt-5-mini": Rates(
            inputPerMillion: 0.25, outputPerMillion: 2,
            cacheCreationPerMillion: 0.25, cacheReadPerMillion: 0.025
        ),
        "gpt-5-nano": Rates(
            inputPerMillion: 0.05, outputPerMillion: 0.4,
            cacheCreationPerMillion: 0.05, cacheReadPerMillion: 0.005
        ),
        // Pro tier — LiteLLM lists no cache-read rate for gpt-5-pro /
        // gpt-5.2-pro (no prompt caching), so 0 is safe: they emit no
        // cache tokens.
        "gpt-5.5-pro": Rates(
            inputPerMillion: 30, outputPerMillion: 180,
            cacheCreationPerMillion: 30, cacheReadPerMillion: 3
        ),
        "gpt-5.4-pro": Rates(
            inputPerMillion: 30, outputPerMillion: 180,
            cacheCreationPerMillion: 30, cacheReadPerMillion: 3
        ),
        "gpt-5.2-pro": Rates(
            inputPerMillion: 21, outputPerMillion: 168,
            cacheCreationPerMillion: 21, cacheReadPerMillion: 0
        ),
        "gpt-5-pro": Rates(
            inputPerMillion: 15, outputPerMillion: 120,
            cacheCreationPerMillion: 15, cacheReadPerMillion: 0
        ),
    ]

    /// Compute the dollar cost of a single TokenEvent. Returns 0 for unknown
    /// models — ccusage parity. Synthetic placeholder models filtered upstream.
    ///
    /// Anthropic's 1M-context tier (2x rate above 200k tokens) is omitted —
    /// it only affects sonnet-4-5 with the 1M flag and is rarely hit in
    /// Claude Code workflows. ccusage's per-bucket threshold check would
    /// disagree with Anthropic's per-position-in-context billing anyway.
    static func cost(for event: TokenEvent) -> Double {
        guard let rates = resolvedRates(for: canonicalModel(event.model), at: event.timestamp) else { return 0 }

        let input = Double(event.inputTokens) / 1_000_000 * rates.inputPerMillion
        let output = Double(event.outputTokens) / 1_000_000 * rates.outputPerMillion
        let cacheCreate = Double(event.cacheCreationTokens) / 1_000_000 * rates.cacheCreationPerMillion
        let cacheRead = Double(event.cacheReadTokens) / 1_000_000 * rates.cacheReadPerMillion

        return input + output + cacheCreate + cacheRead
    }

    /// Whether either source has a price entry for this model. Lets callers
    /// warn the user about unpriced spend without re-implementing the
    /// canonical-name stripping logic.
    static func isKnown(_ rawModel: String) -> Bool {
        resolvedRates(for: canonicalModel(rawModel)) != nil
    }

    /// Remote catalog first, embedded seed second. The seed is what keeps a
    /// catalog that omits a model from silently pricing it at $0.
    private static func resolvedRates(for canonical: String, at date: Date = Date()) -> Rates? {
        // Published Gemini introductory pricing expires on 2027-01-01 UTC.
        // Use event time so importing older CLI records keeps their historical rate.
        if ["gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.8-flash"].contains(canonical) {
            let factor = date.timeIntervalSince1970 < 1_798_761_600 ? 1.0 : 2.0
            return Rates(inputPerMillion: 0.75 * factor, outputPerMillion: 3.75 * factor,
                         cacheCreationPerMillion: 0.75 * factor, cacheReadPerMillion: 0.075 * factor)
        }
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


    /// Strip Anthropic-style date suffixes (e.g. "claude-haiku-4-5-20251001"
    /// → "claude-haiku-4-5") so the snapshot table doesn't need an entry per
    /// pinned release. Exposed for downstream consumers (e.g. per-model
    /// breakdown views) so date-pinned variants group with their base model.
    static func canonicalModelName(_ raw: String) -> String {
        canonicalModel(raw)
    }

    /// Pretty-print the canonical model id for UI rows. Falls back to the
    /// raw id if no friendlier name is wired up yet — better than a blank.
    static func prettyModelName(_ canonical: String) -> String {
        if let name = PricingCatalog.rates(for: canonical)?.displayName, !name.isEmpty {
            return name
        }
        // Anthropic: "claude-opus-4-7" → "Opus 4.7"
        if canonical.hasPrefix("claude-") {
            let trimmed = String(canonical.dropFirst("claude-".count))
            // Split at first dash, then collapse remaining dashes into dots
            // so "opus-4-7" → "opus.4.7" → "Opus 4.7".
            guard let dash = trimmed.firstIndex(of: "-") else {
                return trimmed.capitalized
            }
            let family = String(trimmed[..<dash]).capitalized
            let version = trimmed[trimmed.index(after: dash)...]
                .replacingOccurrences(of: "-", with: ".")
            return "\(family) \(version)"
        }
        // OpenAI: keep as-is, just uppercase the GPT prefix.
        if canonical.hasPrefix("gpt-") {
            return canonical.replacingOccurrences(of: "gpt-", with: "GPT-")
        }
        // OpenAI reasoning family ("o3-pro", "o4-mini-high", etc.) — already
        // short and conventional, capitalize only the leading letter so it
        // matches the typographic weight of "GPT-..." / "Opus 4.7".
        if let first = canonical.first, first == "o", canonical.count > 1,
           canonical.dropFirst().first?.isNumber == true {
            return canonical.prefix(1).uppercased() + canonical.dropFirst()
        }
        return canonical
    }

    private static func canonicalModel(_ raw: String) -> String {
        let raw = raw.hasPrefix("claude-") && raw.hasSuffix("-thinking")
            ? String(raw.dropLast("-thinking".count)) : raw
        guard raw.count > 9 else { return raw }
        let suffixStart = raw.index(raw.endIndex, offsetBy: -9)
        let suffix = raw[suffixStart...]
        guard suffix.first == "-",
              suffix.dropFirst().allSatisfy({ $0.isNumber })
        else { return raw }
        return String(raw[..<suffixStart])
    }
}
